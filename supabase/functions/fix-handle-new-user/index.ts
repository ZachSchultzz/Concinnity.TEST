
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Create Supabase client with service role key
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Fix the handle_new_user function
    const { error } = await supabase.rpc('exec_sql', {
      sql: `
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
          
          -- Create profile with hashed PIN (fixed gen_salt call)
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
            -- Log the error and re-raise
            RAISE EXCEPTION 'Error in handle_new_user: %', SQLERRM;
        END;
        $function$;
      `
    })

    if (error) {
      console.error('Error fixing function:', error)
      return new Response(
        JSON.stringify({ error: 'Failed to fix function' }),
        { 
          status: 500, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    return new Response(
      JSON.stringify({ success: true, message: 'Function fixed successfully' }),
      { 
        status: 200, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )

  } catch (error) {
    console.error('Error:', error)
    return new Response(
      JSON.stringify({ error: 'Function fix failed' }),
      { 
        status: 500, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )
  }
})
