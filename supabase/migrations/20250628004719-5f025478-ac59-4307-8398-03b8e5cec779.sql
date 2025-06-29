
-- Enhanced contacts table with custom fields and segments
CREATE TABLE IF NOT EXISTS public.contacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL,
  user_id UUID NOT NULL,
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL,
  email TEXT NOT NULL,
  phone TEXT,
  company TEXT,
  job_title TEXT,
  status TEXT DEFAULT 'active',
  lead_status TEXT DEFAULT 'new',
  lead_source TEXT,
  lead_score INTEGER DEFAULT 0,
  tags TEXT[] DEFAULT '{}',
  custom_fields JSONB DEFAULT '{}',
  segment_ids UUID[] DEFAULT '{}',
  last_contacted_at TIMESTAMP WITH TIME ZONE,
  next_follow_up TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Contact segments for advanced organization
CREATE TABLE IF NOT EXISTS public.contact_segments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  criteria JSONB NOT NULL,
  color TEXT DEFAULT '#3b82f6',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Enhanced deals table with forecasting
CREATE TABLE IF NOT EXISTS public.deals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL,
  user_id UUID NOT NULL,
  contact_id UUID,
  title TEXT NOT NULL,
  description TEXT,
  value DECIMAL(15,2) NOT NULL DEFAULT 0,
  weighted_value DECIMAL(15,2),
  probability INTEGER DEFAULT 0,
  stage TEXT NOT NULL DEFAULT 'qualification',
  pipeline_id UUID,
  territory_id UUID,
  close_date DATE,
  actual_close_date DATE,
  won_reason TEXT,
  lost_reason TEXT,
  next_action TEXT,
  last_activity_date TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Deal stages for pipeline management
CREATE TABLE IF NOT EXISTS public.deal_stages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL,
  pipeline_id UUID NOT NULL,
  name TEXT NOT NULL,
  probability INTEGER NOT NULL DEFAULT 0,
  order_index INTEGER NOT NULL,
  color TEXT DEFAULT '#3b82f6',
  is_closed BOOLEAN DEFAULT false,
  is_won BOOLEAN DEFAULT false
);

-- Sales pipelines
CREATE TABLE IF NOT EXISTS public.sales_pipelines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  is_default BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Activities with enhanced tracking
CREATE TABLE IF NOT EXISTS public.activities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL,
  user_id UUID NOT NULL,
  contact_id UUID,
  deal_id UUID,
  type TEXT NOT NULL,
  subject TEXT NOT NULL,
  description TEXT,
  status TEXT DEFAULT 'pending',
  priority TEXT DEFAULT 'medium',
  due_date TIMESTAMP WITH TIME ZONE,
  completed_at TIMESTAMP WITH TIME ZONE,
  duration_minutes INTEGER,
  outcome TEXT,
  follow_up_required BOOLEAN DEFAULT false,
  next_follow_up TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Sales territories
CREATE TABLE IF NOT EXISTS public.sales_territories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  manager_id UUID,
  members UUID[] DEFAULT '{}',
  regions TEXT[] DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Workflow automation
CREATE TABLE IF NOT EXISTS public.workflows (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  trigger_type TEXT NOT NULL,
  trigger_conditions JSONB NOT NULL,
  actions JSONB NOT NULL,
  is_active BOOLEAN DEFAULT true,
  created_by UUID NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Sales signals and notifications
CREATE TABLE IF NOT EXISTS public.sales_signals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL,
  user_id UUID NOT NULL,
  contact_id UUID,
  deal_id UUID,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  priority TEXT DEFAULT 'medium',
  action_required BOOLEAN DEFAULT false,
  read BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Email templates
CREATE TABLE IF NOT EXISTS public.email_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL,
  name TEXT NOT NULL,
  subject TEXT NOT NULL,
  content TEXT NOT NULL,
  category TEXT DEFAULT 'general',
  variables TEXT[] DEFAULT '{}',
  created_by UUID NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Advanced analytics tables
CREATE TABLE IF NOT EXISTS public.sales_metrics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL,
  user_id UUID,
  territory_id UUID,
  date DATE NOT NULL,
  metric_type TEXT NOT NULL,
  metric_value DECIMAL(15,2) NOT NULL,
  additional_data JSONB DEFAULT '{}'
);

-- Enable RLS on all tables
ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contact_segments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deal_stages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_pipelines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_territories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_signals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_metrics ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for business-level access
CREATE POLICY "Users can access their business contacts" ON public.contacts
  FOR ALL USING (business_id IN (SELECT business_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Users can access their business segments" ON public.contact_segments
  FOR ALL USING (business_id IN (SELECT business_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Users can access their business deals" ON public.deals
  FOR ALL USING (business_id IN (SELECT business_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Users can access their business stages" ON public.deal_stages
  FOR ALL USING (business_id IN (SELECT business_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Users can access their business pipelines" ON public.sales_pipelines
  FOR ALL USING (business_id IN (SELECT business_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Users can access their business activities" ON public.activities
  FOR ALL USING (business_id IN (SELECT business_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Users can access their business territories" ON public.sales_territories
  FOR ALL USING (business_id IN (SELECT business_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Users can access their business workflows" ON public.workflows
  FOR ALL USING (business_id IN (SELECT business_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Users can access their business signals" ON public.sales_signals
  FOR ALL USING (business_id IN (SELECT business_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Users can access their business templates" ON public.email_templates
  FOR ALL USING (business_id IN (SELECT business_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Users can access their business metrics" ON public.sales_metrics
  FOR ALL USING (business_id IN (SELECT business_id FROM public.profiles WHERE id = auth.uid()));

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_contacts_business_id ON public.contacts(business_id);
CREATE INDEX IF NOT EXISTS idx_contacts_email ON public.contacts(email);
CREATE INDEX IF NOT EXISTS idx_contacts_lead_score ON public.contacts(lead_score DESC);
CREATE INDEX IF NOT EXISTS idx_deals_business_id ON public.deals(business_id);
CREATE INDEX IF NOT EXISTS idx_deals_stage ON public.deals(stage);
CREATE INDEX IF NOT EXISTS idx_deals_close_date ON public.deals(close_date);
CREATE INDEX IF NOT EXISTS idx_activities_business_id ON public.activities(business_id);
CREATE INDEX IF NOT EXISTS idx_activities_due_date ON public.activities(due_date);
CREATE INDEX IF NOT EXISTS idx_sales_signals_user_id ON public.sales_signals(user_id, read);

-- Insert default pipeline and stages
INSERT INTO public.sales_pipelines (business_id, name, description, is_default) 
SELECT DISTINCT business_id, 'Standard Sales Pipeline', 'Default sales pipeline for new deals', true 
FROM public.profiles WHERE business_id IS NOT NULL
ON CONFLICT DO NOTHING;

-- Insert default deal stages
WITH pipeline_data AS (
  SELECT id as pipeline_id, business_id FROM public.sales_pipelines WHERE is_default = true
)
INSERT INTO public.deal_stages (business_id, pipeline_id, name, probability, order_index, color)
SELECT 
  p.business_id, p.pipeline_id, stage_name, probability, order_index, color
FROM pipeline_data p
CROSS JOIN (
  VALUES 
    ('Lead', 10, 1, '#ef4444'),
    ('Qualification', 25, 2, '#f97316'),
    ('Proposal', 50, 3, '#eab308'),
    ('Negotiation', 75, 4, '#22c55e'),
    ('Closed Won', 100, 5, '#10b981'),
    ('Closed Lost', 0, 6, '#6b7280')
) AS stages(stage_name, probability, order_index, color)
ON CONFLICT DO NOTHING;
