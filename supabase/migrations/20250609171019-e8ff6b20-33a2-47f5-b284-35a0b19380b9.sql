
-- Create MFA settings table
CREATE TABLE public.user_mfa_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  is_enabled BOOLEAN DEFAULT FALSE,
  google_auth_enabled BOOLEAN DEFAULT FALSE,
  backup_codes TEXT[], -- Encrypted backup codes
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id)
);

-- Create enhanced audit log table
CREATE TABLE public.security_audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  business_id UUID REFERENCES public.businesses(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL, -- 'auth', 'data_access', 'permission_change', 'security_violation', 'mfa_event'
  event_category TEXT NOT NULL, -- 'authentication', 'authorization', 'data', 'system', 'compliance'
  action TEXT NOT NULL,
  resource TEXT,
  ip_address INET,
  user_agent TEXT,
  session_id TEXT,
  success BOOLEAN NOT NULL,
  risk_level TEXT DEFAULT 'low', -- 'low', 'medium', 'high', 'critical'
  compliance_tags TEXT[], -- ['gdpr', 'sox', 'iso27001', 'pci']
  metadata JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create data encryption settings table
CREATE TABLE public.data_encryption_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID REFERENCES public.businesses(id) ON DELETE CASCADE NOT NULL,
  pii_encryption_enabled BOOLEAN DEFAULT TRUE,
  data_classification_enabled BOOLEAN DEFAULT FALSE,
  retention_policy_days INTEGER DEFAULT 2555, -- 7 years default
  gdpr_compliance_enabled BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(business_id)
);

-- Create advanced session management table
CREATE TABLE public.advanced_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  session_token TEXT UNIQUE NOT NULL,
  device_fingerprint TEXT,
  ip_address INET,
  user_agent TEXT,
  location_country TEXT,
  location_city TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  is_trusted_device BOOLEAN DEFAULT FALSE,
  risk_score INTEGER DEFAULT 0, -- 0-100 risk assessment
  last_activity TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create compliance tracking table
CREATE TABLE public.compliance_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID REFERENCES public.businesses(id) ON DELETE CASCADE NOT NULL,
  framework TEXT NOT NULL, -- 'gdpr', 'sox', 'iso27001', 'pci', 'hipaa'
  event_type TEXT NOT NULL,
  status TEXT NOT NULL, -- 'compliant', 'violation', 'warning', 'resolved'
  description TEXT,
  affected_data_types TEXT[],
  remediation_steps TEXT,
  resolved_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS on all new tables
ALTER TABLE public.user_mfa_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.security_audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.data_encryption_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.advanced_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.compliance_events ENABLE ROW LEVEL SECURITY;

-- RLS Policies for MFA settings
CREATE POLICY "Users can manage their own MFA settings" ON public.user_mfa_settings
  FOR ALL USING (auth.uid() = user_id);

-- RLS Policies for audit logs (read-only for users, managers can see business logs)
CREATE POLICY "Users can view their own audit logs" ON public.security_audit_logs
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Managers can view business audit logs" ON public.security_audit_logs
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() 
      AND business_id = security_audit_logs.business_id 
      AND role IN ('manager', 'admin', 'owner')
    )
  );

-- RLS Policies for encryption settings (admin only)
CREATE POLICY "Admins can manage encryption settings" ON public.data_encryption_settings
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() 
      AND business_id = data_encryption_settings.business_id 
      AND role IN ('admin', 'owner')
    )
  );

-- RLS Policies for advanced sessions
CREATE POLICY "Users can view their own sessions" ON public.advanced_sessions
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own sessions" ON public.advanced_sessions
  FOR UPDATE USING (auth.uid() = user_id);

-- RLS Policies for compliance events
CREATE POLICY "Managers can view compliance events" ON public.compliance_events
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() 
      AND business_id = compliance_events.business_id 
      AND role IN ('manager', 'admin', 'owner')
    )
  );

-- Create indexes for performance
CREATE INDEX idx_security_audit_logs_user_id ON public.security_audit_logs(user_id);
CREATE INDEX idx_security_audit_logs_business_id ON public.security_audit_logs(business_id);
CREATE INDEX idx_security_audit_logs_event_type ON public.security_audit_logs(event_type);
CREATE INDEX idx_security_audit_logs_created_at ON public.security_audit_logs(created_at);
CREATE INDEX idx_advanced_sessions_user_id ON public.advanced_sessions(user_id);
CREATE INDEX idx_advanced_sessions_active ON public.advanced_sessions(is_active);
CREATE INDEX idx_compliance_events_business_id ON public.compliance_events(business_id);
CREATE INDEX idx_compliance_events_framework ON public.compliance_events(framework);

-- Create function for enhanced audit logging
CREATE OR REPLACE FUNCTION public.log_security_event(
  p_user_id UUID,
  p_business_id UUID,
  p_event_type TEXT,
  p_event_category TEXT,
  p_action TEXT,
  p_resource TEXT DEFAULT NULL,
  p_ip_address INET DEFAULT NULL,
  p_user_agent TEXT DEFAULT NULL,
  p_session_id TEXT DEFAULT NULL,
  p_success BOOLEAN DEFAULT TRUE,
  p_risk_level TEXT DEFAULT 'low',
  p_compliance_tags TEXT[] DEFAULT ARRAY[]::TEXT[],
  p_metadata JSONB DEFAULT '{}'::JSONB
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  log_id UUID;
BEGIN
  INSERT INTO public.security_audit_logs (
    user_id, business_id, event_type, event_category, action, resource,
    ip_address, user_agent, session_id, success, risk_level, compliance_tags, metadata
  ) VALUES (
    p_user_id, p_business_id, p_event_type, p_event_category, p_action, p_resource,
    p_ip_address, p_user_agent, p_session_id, p_success, p_risk_level, p_compliance_tags, p_metadata
  ) RETURNING id INTO log_id;
  
  RETURN log_id;
END;
$$;

-- Create function for session risk assessment
CREATE OR REPLACE FUNCTION public.calculate_session_risk(
  p_user_id UUID,
  p_ip_address INET,
  p_user_agent TEXT,
  p_location_country TEXT DEFAULT NULL
) RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  risk_score INTEGER := 0;
  known_ip_count INTEGER;
  known_agent_count INTEGER;
  recent_failed_logins INTEGER;
BEGIN
  -- Check for known IP address
  SELECT COUNT(*) INTO known_ip_count
  FROM public.advanced_sessions
  WHERE user_id = p_user_id AND ip_address = p_ip_address AND is_active = TRUE;
  
  IF known_ip_count = 0 THEN
    risk_score := risk_score + 20; -- New IP address
  END IF;
  
  -- Check for known user agent
  SELECT COUNT(*) INTO known_agent_count
  FROM public.advanced_sessions
  WHERE user_id = p_user_id AND user_agent = p_user_agent;
  
  IF known_agent_count = 0 THEN
    risk_score := risk_score + 15; -- New device/browser
  END IF;
  
  -- Check recent failed login attempts
  SELECT COUNT(*) INTO recent_failed_logins
  FROM public.security_audit_logs
  WHERE user_id = p_user_id 
    AND event_type = 'auth' 
    AND success = FALSE 
    AND created_at > NOW() - INTERVAL '24 hours';
  
  IF recent_failed_logins > 0 THEN
    risk_score := risk_score + (recent_failed_logins * 10);
  END IF;
  
  -- Location-based risk (if available)
  IF p_location_country IS NOT NULL THEN
    -- This would integrate with a threat intelligence service
    -- For now, just a basic check for common high-risk countries
    IF p_location_country = ANY(ARRAY['CN', 'RU', 'KP']) THEN
      risk_score := risk_score + 25;
    END IF;
  END IF;
  
  -- Cap the risk score at 100
  RETURN LEAST(risk_score, 100);
END;
$$;
