
import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.8';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const openAIApiKey = Deno.env.get('OPENAI_API_KEY');
const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { contactId, emailType, context, businessId } = await req.json();
    
    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    
    // Fetch contact details
    const { data: contact } = await supabase
      .from('contacts')
      .select('*')
      .eq('id', contactId)
      .single();

    // Fetch business details for personalization
    const { data: business } = await supabase
      .from('businesses')
      .select('*')
      .eq('id', businessId)
      .single();

    if (!openAIApiKey) {
      // Fallback template
      return new Response(JSON.stringify({
        subject: `Follow-up from ${business?.business_name || 'our team'}`,
        body: `Hi ${contact?.first_name || 'there'},\n\nI wanted to follow up on our recent conversation. ${context || 'Let me know if you have any questions.'}\n\nBest regards,\n[Your name]`,
        tone: 'professional'
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const emailPrompt = `
      Generate a personalized ${emailType || 'follow-up'} email for:
      
      Contact: ${contact?.first_name} ${contact?.last_name}
      Company: ${contact?.company}
      Context: ${context || 'General follow-up'}
      Business: ${business?.business_name}
      
      Create a professional, engaging email that:
      1. Is personalized to the contact
      2. References the specific context
      3. Has a clear call-to-action
      4. Maintains a ${emailType === 'cold_outreach' ? 'friendly but professional' : 'warm and professional'} tone
      
      Return JSON with:
      {
        "subject": "compelling subject line",
        "body": "full email body with proper formatting",
        "tone": "professional|friendly|formal",
        "cta": "main call to action"
      }
    `;

    const openAIResponse = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openAIApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          { role: 'system', content: 'You are an expert sales email writer. Create personalized, effective sales emails that drive engagement and responses. Always return valid JSON.' },
          { role: 'user', content: emailPrompt }
        ],
        temperature: 0.7,
      }),
    });

    if (openAIResponse.ok) {
      const aiData = await openAIResponse.json();
      const aiContent = aiData.choices[0].message.content;
      
      try {
        const emailTemplate = JSON.parse(aiContent);
        return new Response(JSON.stringify(emailTemplate), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      } catch (parseError) {
        console.error('Error parsing AI response:', parseError);
      }
    }

    // Fallback if OpenAI fails
    return new Response(JSON.stringify({
      subject: `Follow-up from ${business?.business_name || 'our team'}`,
      body: `Hi ${contact?.first_name || 'there'},\n\nI wanted to follow up on our recent conversation about ${context || 'your needs'}.\n\nWould you be available for a quick call this week to discuss next steps?\n\nBest regards,\n[Your name]`,
      tone: 'professional',
      cta: 'Schedule a call'
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (error) {
    console.error('Error in ai-email-generator:', error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
