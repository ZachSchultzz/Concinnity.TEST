
-- First, let's add the missing business_id column to the profiles table
ALTER TABLE public.profiles 
ADD COLUMN business_id uuid REFERENCES public.businesses(id);

-- Add the role column back to profiles table for proper role assignment
ALTER TABLE public.profiles 
ADD COLUMN role user_role DEFAULT 'employee'::user_role;

-- Update the handle_new_user function to properly handle business_id and role assignment
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
    role,
    business_id
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
    END,
    -- For now, set business_id to NULL - this can be updated during onboarding
    NULL
  );
  
  RETURN NEW;
END;
$$;

-- Update the employee count trigger to handle NULL business_id properly
CREATE OR REPLACE FUNCTION public.update_business_employee_count()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.business_id IS NOT NULL THEN
            UPDATE public.businesses 
            SET current_employee_count = COALESCE(current_employee_count, 0) + 1
            WHERE id = NEW.business_id;
        END IF;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        IF OLD.business_id IS NOT NULL THEN
            UPDATE public.businesses 
            SET current_employee_count = GREATEST(COALESCE(current_employee_count, 0) - 1, 0)
            WHERE id = OLD.business_id;
        END IF;
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        -- Handle business_id changes
        IF OLD.business_id IS DISTINCT FROM NEW.business_id THEN
            IF OLD.business_id IS NOT NULL THEN
                UPDATE public.businesses 
                SET current_employee_count = GREATEST(COALESCE(current_employee_count, 0) - 1, 0)
                WHERE id = OLD.business_id;
            END IF;
            IF NEW.business_id IS NOT NULL THEN
                UPDATE public.businesses 
                SET current_employee_count = COALESCE(current_employee_count, 0) + 1
                WHERE id = NEW.business_id;
            END IF;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;
