
-- Add missing RLS policies for tables that currently lack them

-- Enable RLS on tables that don't have it yet
ALTER TABLE public.compliance_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.data_encryption_settings ENABLE ROW LEVEL SECURITY;

-- Add RLS policies for compliance_events table
CREATE POLICY "Users can view compliance events for their business" 
  ON public.compliance_events 
  FOR SELECT 
  USING (
    business_id IN (
      SELECT business_id FROM public.profiles WHERE id = auth.uid()
    )
  );

CREATE POLICY "Admins can manage compliance events for their business" 
  ON public.compliance_events 
  FOR ALL 
  USING (
    business_id IN (
      SELECT business_id FROM public.profiles WHERE id = auth.uid()
    ) AND
    public.user_has_permission(auth.uid(), 'system.admin')
  );

-- Add RLS policies for data_encryption_settings table  
CREATE POLICY "Users can view encryption settings for their business" 
  ON public.data_encryption_settings 
  FOR SELECT 
  USING (
    business_id IN (
      SELECT business_id FROM public.profiles WHERE id = auth.uid()
    )
  );

CREATE POLICY "Admins can manage encryption settings for their business" 
  ON public.data_encryption_settings 
  FOR ALL 
  USING (
    business_id IN (
      SELECT business_id FROM public.profiles WHERE id = auth.uid()
    ) AND
    public.user_has_permission(auth.uid(), 'system.admin')
  );

-- Add RLS policies for file_versions table
ALTER TABLE public.file_versions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view file versions they created or have access to" 
  ON public.file_versions 
  FOR SELECT 
  USING (
    created_by = auth.uid() OR
    file_id IN (
      SELECT id FROM public.files WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can create file versions for files they own" 
  ON public.file_versions 
  FOR INSERT 
  WITH CHECK (
    created_by = auth.uid() AND
    file_id IN (
      SELECT id FROM public.files WHERE user_id = auth.uid()
    )
  );

-- Restrict business_types and industries to authenticated users only
ALTER TABLE public.business_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.industries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view business types" 
  ON public.business_types 
  FOR SELECT 
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can view industries" 
  ON public.industries 
  FOR SELECT 
  TO authenticated
  USING (true);

-- Update profiles table to include additional security fields
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS last_login TIMESTAMP WITH TIME ZONE;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS pin_hash TEXT;

-- Add security function to verify PIN
CREATE OR REPLACE FUNCTION public.verify_pin(user_id uuid, input_pin text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  stored_hash text;
BEGIN
  SELECT pin_hash INTO stored_hash FROM public.profiles WHERE id = user_id;
  
  IF stored_hash IS NULL THEN
    RETURN false;
  END IF;
  
  -- In production, use proper password hashing like bcrypt
  -- For now, using simple hash comparison
  RETURN stored_hash = crypt(input_pin, stored_hash);
END;
$$;
