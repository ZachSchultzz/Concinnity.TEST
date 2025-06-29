
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
    const { email, bin, password, pin, firstName, lastName, businessName } = await req.json()

    console.log('Registration attempt for:', { email, bin, firstName, lastName, businessName })

    // Validate required fields
    if (!email || !bin || !password || !pin || !firstName || !lastName) {
      console.log('Validation failed: missing required fields')
      return new Response(
        JSON.stringify({ error: 'All required fields must be provided' }),
        { 
          status: 400, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    // Basic PIN validation - just check it's 4-6 digits
    if (!/^\d{4,6}$/.test(pin)) {
      console.log('Validation failed: invalid PIN format')
      return new Response(
        JSON.stringify({ error: 'PIN must be 4-6 digits' }),
        { 
          status: 400, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    // Create Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    console.log('Creating user with metadata...')

    // Create user with proper metadata to satisfy the trigger
    const { data: authData, error: authError } = await supabase.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        bin: bin,
        pin: pin,
        first_name: firstName,
        last_name: lastName,
        business_name: businessName || `${bin} Business`
      }
    })

    if (authError) {
      console.error('User creation failed:', authError)
      
      // Provide more specific error messages
      if (authError.message.includes('duplicate') || authError.message.includes('already')) {
        return new Response(
          JSON.stringify({ error: 'An account with this email already exists. Please try signing in instead.' }),
          { 
            status: 400, 
            headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
          }
        )
      }
      
      if (authError.message.includes('PIN does not meet security requirements')) {
        return new Response(
          JSON.stringify({ error: 'PIN is too weak. Avoid sequential numbers (1234), repeated digits (1111), or common patterns.' }),
          { 
            status: 400, 
            headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
          }
        )
      }
      
      return new Response(
        JSON.stringify({ error: authError.message || 'Registration failed' }),
        { 
          status: 400, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    if (!authData.user) {
      console.error('No user data returned after creation')
      return new Response(
        JSON.stringify({ error: 'Registration failed - no user created' }),
        { 
          status: 500, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    console.log('User created successfully:', authData.user.id)

    // Create business record if BIN and business name are provided
    let businessId = null;
    if (bin && businessName) {
      console.log('Creating business record...');
      const { data: businessData, error: businessError } = await supabase
        .from('businesses')
        .insert({
          bin: bin,
          business_name: businessName,
          verification_status: 'pending'
        })
        .select()
        .single();

      if (businessError) {
        console.error('Business creation failed:', businessError);
        // Don't fail registration if business creation fails
      } else {
        businessId = businessData?.id;
        console.log('Business created successfully:', businessId);
      }
    }

    return new Response(
      JSON.stringify({ 
        success: true, 
        message: 'Registration successful. You can now sign in.',
        user_id: authData.user.id,
        business_id: businessId
      }),
      { 
        status: 200, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )

  } catch (error) {
    console.error('Registration error:', error)
    return new Response(
      JSON.stringify({ error: 'Registration failed: ' + error.message }),
      { 
        status: 500, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )
  }
})
