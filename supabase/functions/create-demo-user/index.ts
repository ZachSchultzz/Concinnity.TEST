
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

    // Demo user credentials
    const demoUser = {
      email: "demo@concinnity.com",
      bin: "DEMO123456",
      password: "demo123",
      pin: "9173",
      firstName: "Demo",
      lastName: "User",
      businessName: "Demo Business Inc."
    }

    console.log('Creating/checking demo user:', demoUser.email)

    // Check if demo user already exists
    const { data: existingUser, error: checkError } = await supabase
      .from('profiles')
      .select('id')
      .eq('email', demoUser.email)
      .single()

    if (checkError && checkError.code !== 'PGRST116') {
      console.error('Error checking for existing user:', checkError)
    }

    if (existingUser) {
      console.log('Demo user already exists, user can login directly')
      return new Response(
        JSON.stringify({ 
          success: true, 
          message: 'Demo user ready',
          credentials: {
            email: demoUser.email,
            bin: demoUser.bin,
            password: demoUser.password,
            pin: demoUser.pin
          }
        }),
        { 
          status: 200, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    console.log('Creating new demo user...')

    // Create demo user with proper metadata for the trigger
    const { data: authData, error: authError } = await supabase.auth.admin.createUser({
      email: demoUser.email,
      password: demoUser.password,
      email_confirm: true,
      user_metadata: {
        bin: demoUser.bin,
        pin: demoUser.pin,
        first_name: demoUser.firstName,
        last_name: demoUser.lastName,
        business_name: demoUser.businessName
      }
    })

    if (authError) {
      console.error('Failed to create demo user:', authError)
      return new Response(
        JSON.stringify({ error: 'Failed to create demo user: ' + authError.message }),
        { 
          status: 500, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    if (!authData.user) {
      console.error('No user data returned after demo user creation')
      return new Response(
        JSON.stringify({ error: 'Failed to create demo user - no user data returned' }),
        { 
          status: 500, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    console.log('Demo user created successfully:', authData.user.id)

    return new Response(
      JSON.stringify({ 
        success: true, 
        message: 'Demo user created successfully',
        user_id: authData.user.id,
        credentials: {
          email: demoUser.email,
          bin: demoUser.bin,
          password: demoUser.password,
          pin: demoUser.pin
        }
      }),
      { 
        status: 200, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )

  } catch (error) {
    console.error('Error with demo user:', error)
    return new Response(
      JSON.stringify({ error: 'Demo user setup failed: ' + error.message }),
      { 
        status: 500, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )
  }
})
