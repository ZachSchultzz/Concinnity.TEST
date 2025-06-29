
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
    const { email, bin, password, pin } = await req.json()

    console.log('Login attempt for:', { email, bin })

    // Validate required fields
    if (!email || !bin || !password || !pin) {
      return new Response(
        JSON.stringify({ error: 'All fields are required' }),
        { 
          status: 400, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    // Validate PIN format
    if (!/^\d{4,6}$/.test(pin)) {
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

    // First authenticate with Supabase Auth
    const { data: authData, error: authError } = await supabase.auth.signInWithPassword({
      email,
      password
    })

    if (authError || !authData.user) {
      console.log('Auth failed:', authError?.message)
      return new Response(
        JSON.stringify({ error: 'Invalid email or password' }),
        { 
          status: 401, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    console.log('Auth successful for user:', authData.user.id)

    // Get user profile with business info
    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select(`
        id, business_id, email, first_name, last_name, role, is_active, pin_hash,
        businesses!inner (
          id, bin, business_name
        )
      `)
      .eq('id', authData.user.id)
      .eq('businesses.bin', bin)
      .single()

    if (profileError || !profile) {
      console.log('Profile not found or BIN mismatch:', profileError)
      return new Response(
        JSON.stringify({ error: 'Invalid credentials or business identification' }),
        { 
          status: 401, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    // Use the database function for PIN verification
    const { data: pinValid, error: pinError } = await supabase.rpc('verify_pin', {
      user_id: authData.user.id,
      input_pin: pin
    })
    
    if (pinError) {
      console.log('PIN verification error:', pinError)
      return new Response(
        JSON.stringify({ error: 'PIN verification failed' }),
        { 
          status: 401, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    if (!pinValid) {
      console.log('PIN verification failed')
      return new Response(
        JSON.stringify({ error: 'Invalid PIN' }),
        { 
          status: 401, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    console.log('PIN verification successful')

    // Update last login (optional, don't fail if it errors)
    try {
      await supabase
        .from('profiles')
        .update({ last_login: new Date().toISOString() })
        .eq('id', authData.user.id)
    } catch (updateError) {
      console.log('Last login update failed (non-critical):', updateError)
    }

    // Create secure session
    const sessionToken = crypto.randomUUID()
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000) // 24 hours

    // Try to create session record (optional, don't fail if it errors)
    try {
      await supabase
        .from('business_sessions')
        .insert({
          user_id: authData.user.id,
          business_id: profile.business_id,
          session_token: sessionToken,
          ip_address: req.headers.get('x-forwarded-for')?.split(',')[0] || null,
          user_agent: req.headers.get('user-agent') || null,
          expires_at: expiresAt.toISOString()
        })
    } catch (sessionError) {
      console.log('Session creation failed (non-critical):', sessionError)
    }

    console.log('Login completed successfully')

    return new Response(
      JSON.stringify({
        success: true,
        user: {
          id: authData.user.id,
          email: profile.email,
          first_name: profile.first_name,
          last_name: profile.last_name,
          role: profile.role
        },
        business: {
          id: profile.businesses.id,
          name: profile.businesses.business_name,
          bin: profile.businesses.bin
        },
        session: {
          token: sessionToken,
          expires_at: expiresAt.toISOString()
        }
      }),
      { 
        status: 200, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )

  } catch (error) {
    console.error('Login error:', error)
    return new Response(
      JSON.stringify({ error: 'Login failed: ' + error.message }),
      { 
        status: 500, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )
  }
})
