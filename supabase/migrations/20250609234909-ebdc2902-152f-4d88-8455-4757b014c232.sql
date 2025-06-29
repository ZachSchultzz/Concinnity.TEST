
-- Enable the pgcrypto extension for secure password hashing
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Update the handle_new_user function to include better error handling
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  business_record RECORD;
  user_bin TEXT;
  user_pin TEXT;
  user_business_name TEXT;
  is_first_user BOOLEAN;
BEGIN
  -- Extract data from raw_user_meta_data
  user_bin := NEW.raw_user_meta_data ->> 'bin';
  user_pin := NEW.raw_user_meta_data ->> 'pin';
  user_business_name := NEW.raw_user_meta_data ->> 'business_name';
  
  -- Validate required data
  IF user_bin IS NULL OR user_pin IS NULL THEN
    RAISE EXCEPTION 'Missing required user data: bin or pin';
  END IF;
  
  -- Validate PIN strength
  IF NOT public.validate_pin_strength(user_pin) THEN
    RAISE EXCEPTION 'PIN does not meet security requirements. Avoid sequential numbers, repeated digits, or common patterns.';
  END IF;
  
  -- Find or create business
  SELECT * INTO business_record FROM public.businesses WHERE bin = user_bin;
  
  IF business_record IS NULL THEN
    -- Create new business
    INSERT INTO public.businesses (bin, business_name)
    VALUES (user_bin, COALESCE(user_business_name, user_bin || ' Business'))
    RETURNING * INTO business_record;
    
    is_first_user := TRUE;
  ELSE
    is_first_user := FALSE;
  END IF;
  
  -- Create profile with hashed PIN (now with pgcrypto extension enabled)
  INSERT INTO public.profiles (
    id,
    business_id,
    email,
    first_name,
    last_name,
    pin_hash,
    role
  ) VALUES (
    NEW.id,
    business_record.id,
    NEW.email,
    NEW.raw_user_meta_data ->> 'first_name',
    NEW.raw_user_meta_data ->> 'last_name',
    crypt(user_pin, gen_salt('bf')),
    CASE 
      WHEN is_first_user THEN 'owner'::user_role
      ELSE 'employee'::user_role
    END
  );
  
  -- Create onboarding progress for first user
  IF is_first_user THEN
    INSERT INTO public.onboarding_progress (
      business_id,
      user_id,
      current_step,
      user_setup_completed
    ) VALUES (
      business_record.id,
      NEW.id,
      1,
      true
    );
  END IF;
  
  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- Log the error and re-raise with more context
    RAISE EXCEPTION 'Error in handle_new_user: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
END;
$function$;
