
-- Call logs for tracking communications
CREATE TABLE IF NOT EXISTS public.call_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL,
  user_id UUID NOT NULL,
  contact_id UUID,
  deal_id UUID,
  phone_number TEXT NOT NULL,
  call_type TEXT NOT NULL, -- 'inbound', 'outbound'
  duration_seconds INTEGER DEFAULT 0,
  status TEXT DEFAULT 'completed', -- 'completed', 'missed', 'busy', 'no_answer'
  notes TEXT,
  recording_url TEXT,
  call_started_at TIMESTAMP WITH TIME ZONE NOT NULL,
  call_ended_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Advanced lead scoring factors
CREATE TABLE IF NOT EXISTS public.lead_scoring_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  trigger_field TEXT NOT NULL, -- 'email_opened', 'page_visited', 'form_submitted', etc.
  trigger_condition JSONB NOT NULL,
  score_change INTEGER NOT NULL,
  is_active BOOLEAN DEFAULT true,
  created_by UUID NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Territory assignments and management
CREATE TABLE IF NOT EXISTS public.territory_assignments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  territory_id UUID NOT NULL,
  user_id UUID NOT NULL,
  role TEXT DEFAULT 'member', -- 'manager', 'member'
  assigned_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  assigned_by UUID NOT NULL,
  UNIQUE(territory_id, user_id)
);

-- Workflow execution history
CREATE TABLE IF NOT EXISTS public.workflow_executions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id UUID NOT NULL,
  trigger_data JSONB NOT NULL,
  execution_status TEXT DEFAULT 'running', -- 'running', 'completed', 'failed'
  steps_completed INTEGER DEFAULT 0,
  total_steps INTEGER NOT NULL,
  error_message TEXT,
  started_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  completed_at TIMESTAMP WITH TIME ZONE
);

-- Lead behavioral tracking
CREATE TABLE IF NOT EXISTS public.lead_activities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL,
  contact_id UUID NOT NULL,
  activity_type TEXT NOT NULL, -- 'email_opened', 'link_clicked', 'page_visited', 'form_submitted'
  activity_data JSONB DEFAULT '{}',
  score_impact INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Advanced sales forecasting data
CREATE TABLE IF NOT EXISTS public.sales_forecasts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL,
  user_id UUID,
  territory_id UUID,
  forecast_period TEXT NOT NULL, -- 'monthly', 'quarterly', 'yearly'
  forecast_date DATE NOT NULL,
  forecasted_revenue DECIMAL(15,2) NOT NULL,
  confidence_level INTEGER DEFAULT 70,
  pipeline_value DECIMAL(15,2) NOT NULL,
  weighted_pipeline DECIMAL(15,2) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Enable RLS on new tables
ALTER TABLE public.call_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_scoring_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.territory_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_executions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_forecasts ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY "Users can access their business call logs" ON public.call_logs
  FOR ALL USING (business_id IN (SELECT business_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Users can access their business lead scoring rules" ON public.lead_scoring_rules
  FOR ALL USING (business_id IN (SELECT business_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Users can access their territory assignments" ON public.territory_assignments
  FOR ALL USING (territory_id IN (SELECT id FROM public.sales_territories WHERE business_id IN (SELECT business_id FROM public.profiles WHERE id = auth.uid())));

CREATE POLICY "Users can access their business workflow executions" ON public.workflow_executions
  FOR ALL USING (workflow_id IN (SELECT id FROM public.workflows WHERE business_id IN (SELECT business_id FROM public.profiles WHERE id = auth.uid())));

CREATE POLICY "Users can access their business lead activities" ON public.lead_activities
  FOR ALL USING (business_id IN (SELECT business_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Users can access their business sales forecasts" ON public.sales_forecasts
  FOR ALL USING (business_id IN (SELECT business_id FROM public.profiles WHERE id = auth.uid()));

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_call_logs_business_id ON public.call_logs(business_id);
CREATE INDEX IF NOT EXISTS idx_call_logs_contact_id ON public.call_logs(contact_id);
CREATE INDEX IF NOT EXISTS idx_call_logs_call_started_at ON public.call_logs(call_started_at DESC);
CREATE INDEX IF NOT EXISTS idx_lead_activities_contact_id ON public.lead_activities(contact_id);
CREATE INDEX IF NOT EXISTS idx_lead_activities_created_at ON public.lead_activities(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_workflow_executions_workflow_id ON public.workflow_executions(workflow_id);
CREATE INDEX IF NOT EXISTS idx_sales_forecasts_business_id ON public.sales_forecasts(business_id, forecast_date);

-- Insert default lead scoring rules
INSERT INTO public.lead_scoring_rules (business_id, name, description, trigger_field, trigger_condition, score_change, created_by)
SELECT DISTINCT 
  p.business_id,
  rule_name,
  rule_description,
  trigger_field,
  trigger_condition::jsonb,
  score_change,
  p.id
FROM public.profiles p
CROSS JOIN (
  VALUES 
    ('Email Opened', 'Points awarded when contact opens an email', 'email_opened', '{}', 5),
    ('Link Clicked', 'Points awarded when contact clicks email link', 'link_clicked', '{}', 10),
    ('Website Visit', 'Points awarded for website visits', 'page_visited', '{"pages": ["pricing", "features"]}', 15),
    ('Form Submitted', 'Points awarded when contact submits a form', 'form_submitted', '{}', 25),
    ('Demo Requested', 'High value action - demo request', 'demo_requested', '{}', 50)
) AS rules(rule_name, rule_description, trigger_field, trigger_condition, score_change)
WHERE p.business_id IS NOT NULL
ON CONFLICT DO NOTHING;

-- Function to automatically calculate weighted deal values
CREATE OR REPLACE FUNCTION update_deal_weighted_value()
RETURNS TRIGGER AS $$
BEGIN
  NEW.weighted_value = (NEW.value * NEW.probability) / 100.0;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to update weighted values automatically
DROP TRIGGER IF EXISTS trigger_update_deal_weighted_value ON public.deals;
CREATE TRIGGER trigger_update_deal_weighted_value
  BEFORE INSERT OR UPDATE OF value, probability ON public.deals
  FOR EACH ROW EXECUTE FUNCTION update_deal_weighted_value();
