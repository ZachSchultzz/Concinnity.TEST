
-- Clean up existing complex authentication system and create simplified version
-- First drop all dependent policies

-- Drop policies that depend on business_id
DROP POLICY IF EXISTS "Users can only see their own business" ON public.businesses;
DROP POLICY IF EXISTS "Users can see profiles in their business" ON public.profiles;
DROP POLICY IF EXISTS "Managers can view business audit logs" ON public.security_audit_logs;
DROP POLICY IF EXISTS "Admins can manage encryption settings" ON public.data_encryption_settings;
DROP POLICY IF EXISTS "Managers can view compliance events" ON public.compliance_events;

-- Drop any other existing policies on profiles
DROP POLICY IF EXISTS "Users can view their own profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users can update their own profiles" ON public.profiles;

-- Now drop complex tables and functions
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
DROP FUNCTION IF EXISTS public.verify_pin(uuid, text) CASCADE;
DROP FUNCTION IF EXISTS public.validate_pin_strength(text) CASCADE;

-- Drop complex business-related tables
DROP TABLE IF EXISTS public.business_sessions CASCADE;
DROP TABLE IF EXISTS public.auth_attempts CASCADE;
DROP TABLE IF EXISTS public.employee_invitations CASCADE;
DROP TABLE IF EXISTS public.onboarding_progress CASCADE;
DROP TABLE IF EXISTS public.onboarding_workflow_steps CASCADE;
DROP TABLE IF EXISTS public.onboarding_notifications CASCADE;
DROP TABLE IF EXISTS public.new_hire_onboarding CASCADE;

-- Now we can safely drop the columns from profiles
ALTER TABLE public.profiles DROP COLUMN IF EXISTS pin_hash;
ALTER TABLE public.profiles DROP COLUMN IF EXISTS business_id;
ALTER TABLE public.profiles DROP COLUMN IF EXISTS role;
ALTER TABLE public.profiles DROP COLUMN IF EXISTS last_login;
ALTER TABLE public.profiles DROP COLUMN IF EXISTS is_active;

-- Add simple profile fields
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS full_name text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS avatar_url text;

-- Create simple handle_new_user function
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.profiles (
    id,
    email,
    first_name,
    last_name,
    full_name
  ) VALUES (
    NEW.id,
    NEW.email,
    NEW.raw_user_meta_data ->> 'first_name',
    NEW.raw_user_meta_data ->> 'last_name',
    COALESCE(
      (NEW.raw_user_meta_data ->> 'first_name') || ' ' || (NEW.raw_user_meta_data ->> 'last_name'),
      NEW.email
    )
  );
  
  RETURN NEW;
END;
$function$;

-- Create trigger for new users
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Enable RLS on profiles
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Create simple RLS policies
CREATE POLICY "Users can view own profile" 
  ON public.profiles 
  FOR SELECT 
  USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" 
  ON public.profiles 
  FOR UPDATE 
  USING (auth.uid() = id);
