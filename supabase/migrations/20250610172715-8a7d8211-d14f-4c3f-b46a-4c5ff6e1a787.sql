
-- Create a function to check if an email is authorized for super admin access
CREATE OR REPLACE FUNCTION public.is_super_admin_email(email_address text)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
AS $$
  SELECT email_address = 'schultz@concinnity.vision';
$$;

-- Add super admin permissions to role_permissions table
INSERT INTO public.role_permissions (role, permission, description) VALUES
('super_admin', 'platform_admin', 'Full platform administration access'),
('super_admin', 'cross_business_access', 'Access to all businesses on the platform'),
('super_admin', 'system_configuration', 'Modify core system settings'),
('super_admin', 'user_management_global', 'Manage all users across all businesses'),
('super_admin', 'system.audit_logs', 'View all system audit logs'),
('super_admin', 'system.security_monitoring', 'Access security monitoring across all businesses')
ON CONFLICT (role, permission) DO NOTHING;

-- Update the auth registration trigger to automatically assign super_admin role
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  INSERT INTO public.profiles (
    id,
    email,
    first_name,
    last_name,
    full_name,
    role
  ) VALUES (
    NEW.id,
    NEW.email,
    NEW.raw_user_meta_data ->> 'first_name',
    NEW.raw_user_meta_data ->> 'last_name',
    COALESCE(
      (NEW.raw_user_meta_data ->> 'first_name') || ' ' || (NEW.raw_user_meta_data ->> 'last_name'),
      NEW.email
    ),
    CASE 
      WHEN public.is_super_admin_email(NEW.email) THEN 'super_admin'::user_role
      ELSE 'employee'::user_role
    END
  );
  
  RETURN NEW;
END;
$$;
