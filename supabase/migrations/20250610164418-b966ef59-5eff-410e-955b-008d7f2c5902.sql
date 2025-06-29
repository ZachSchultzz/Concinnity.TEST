
-- Create the missing function first
CREATE OR REPLACE FUNCTION public.update_business_employee_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.business_id IS NOT NULL THEN
            UPDATE public.businesses 
            SET current_employee_count = current_employee_count + 1
            WHERE id = NEW.business_id;
        END IF;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        IF OLD.business_id IS NOT NULL THEN
            UPDATE public.businesses 
            SET current_employee_count = GREATEST(current_employee_count - 1, 0)
            WHERE id = OLD.business_id;
        END IF;
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        -- Handle business_id changes
        IF OLD.business_id IS DISTINCT FROM NEW.business_id THEN
            IF OLD.business_id IS NOT NULL THEN
                UPDATE public.businesses 
                SET current_employee_count = GREATEST(current_employee_count - 1, 0)
                WHERE id = OLD.business_id;
            END IF;
            IF NEW.business_id IS NOT NULL THEN
                UPDATE public.businesses 
                SET current_employee_count = current_employee_count + 1
                WHERE id = NEW.business_id;
            END IF;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

-- Now create the trigger
DROP TRIGGER IF EXISTS trigger_update_employee_count ON public.profiles;
CREATE TRIGGER trigger_update_employee_count
    AFTER INSERT OR UPDATE OR DELETE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.update_business_employee_count();

-- Add PIN strength validation function
CREATE OR REPLACE FUNCTION public.validate_pin_strength(pin_input TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Check if PIN is 4-6 digits
    IF NOT (pin_input ~ '^[0-9]{4,6}$') THEN
        RETURN FALSE;
    END IF;
    
    -- Check for sequential numbers (1234, 2345, etc.)
    IF pin_input ~ '0123|1234|2345|3456|4567|5678|6789' THEN
        RETURN FALSE;
    END IF;
    
    -- Check for repeated digits (1111, 2222, etc.)
    IF pin_input ~ '^(\d)\1+$' THEN
        RETURN FALSE;
    END IF;
    
    -- Check for common weak patterns
    IF pin_input IN ('0000', '1111', '2222', '3333', '4444', '5555', '6666', '7777', '8888', '9999', '1234', '4321', '0001', '1001') THEN
        RETURN FALSE;
    END IF;
    
    RETURN TRUE;
END;
$$;
