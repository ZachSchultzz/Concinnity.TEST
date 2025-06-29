
-- Add MFA columns to user_mfa_settings table if they don't exist
ALTER TABLE public.user_mfa_settings 
ADD COLUMN IF NOT EXISTS secret_key TEXT,
ADD COLUMN IF NOT EXISTS last_used_at TIMESTAMP WITH TIME ZONE;

-- Create MFA verification attempts table for security monitoring
CREATE TABLE IF NOT EXISTS public.mfa_verification_attempts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  attempt_type TEXT NOT NULL, -- 'totp' or 'backup_code'
  success BOOLEAN NOT NULL,
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS on MFA verification attempts
ALTER TABLE public.mfa_verification_attempts ENABLE ROW LEVEL SECURITY;

-- RLS policy for MFA verification attempts
CREATE POLICY "Users can view their own MFA attempts" ON public.mfa_verification_attempts
  FOR SELECT USING (auth.uid() = user_id);

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_mfa_verification_attempts_user_id 
ON public.mfa_verification_attempts(user_id);

-- Function to verify backup codes
CREATE OR REPLACE FUNCTION public.verify_backup_code(
  p_user_id UUID,
  p_backup_code TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  current_codes TEXT[];
  updated_codes TEXT[];
BEGIN
  -- Get current backup codes
  SELECT backup_codes INTO current_codes
  FROM public.user_mfa_settings
  WHERE user_id = p_user_id AND is_enabled = TRUE;
  
  -- Check if backup code exists
  IF current_codes IS NULL OR NOT (p_backup_code = ANY(current_codes)) THEN
    RETURN FALSE;
  END IF;
  
  -- Remove used backup code
  SELECT ARRAY(
    SELECT unnest(current_codes) 
    EXCEPT 
    SELECT p_backup_code
  ) INTO updated_codes;
  
  -- Update backup codes
  UPDATE public.user_mfa_settings
  SET backup_codes = updated_codes,
      updated_at = NOW()
  WHERE user_id = p_user_id;
  
  RETURN TRUE;
END;
$$;
