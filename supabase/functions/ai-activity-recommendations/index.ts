
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
    const { businessId, contactId, dealId } = await req.json();
    
    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    
    // Fetch relevant data based on request
    let contextData: any = {};
    
    if (contactId) {
      const { data: contact } = await supabase
        .from('contacts')
        .select('*')
        .eq('id', contactId)
        .single();
      contextData.contact = contact;
    }
    
    if (dealId) {
      const { data: deal } = await supabase
        .from('deals')
        .select('*')
        .eq('id', dealId)
        .single();
      contextData.deal = deal;
    }

    // Fetch recent activities for context
    const { data: activities } = await supabase
      .from('activities')
      .select('*')
      .eq('business_id', businessId)
      .order('created_at', { ascending: false })
      .limit(5);

    contextData.recentActivities = activities || [];

    if (!openAIApiKey) {
      // Fallback recommendations
      return new Response(JSON.stringify({
        recommendations: [
          {
            type: 'follow_up_call',
            priority: 'high',
            title: 'Schedule follow-up call',
            description: 'Contact showed interest in last interaction',
            suggestedDate: new Date(Date.now() + 2 * 24 * 60 * 60 * 1000).toISOString(),
            reasoning: 'Based on recent engagement patterns'
          },
          {
            type: 'send_proposal',
            priority: 'medium',
            title: 'Send detailed proposal',
            description: 'Customer is ready for next step in sales process',
            suggestedDate: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
            reasoning: 'Timeline indicates readiness for proposal'
          }
        ]
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const recommendationPrompt = `
      Analyze this CRM context and suggest next best actions:
      
      Context Data: ${JSON.stringify(contextData, null, 2)}
      
      Based on the contact/deal information and recent activities, suggest 3-5 specific actions that would move the sales process forward. Consider:
      - Contact engagement level
      - Deal stage and progression
      - Time since last interaction
      - Urgency and priority
      
      Return JSON array with structure:
      [{
        "type": "call|email|meeting|proposal|demo|follow_up",
        "priority": "high|medium|low",
        "title": "Action title",
        "description": "Detailed description",
        "suggestedDate": "ISO date string",
        "reasoning": "Why this action is recommended",
        "estimatedDuration": "time estimate"
      }]
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
          { role: 'system', content: 'You are a sales strategy expert. Analyze CRM data and provide actionable next-step recommendations that will advance sales opportunities. Always return valid JSON.' },
          { role: 'user', content: recommendationPrompt }
        ],
        temperature: 0.4,
      }),
    });

    if (openAIResponse.ok) {
      const aiData = await openAIResponse.json();
      const aiContent = aiData.choices[0].message.content;
      
      try {
        const recommendations = JSON.parse(aiContent);
        return new Response(JSON.stringify({ 
          recommendations,
          generatedAt: new Date().toISOString()
        }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      } catch (parseError) {
        console.error('Error parsing AI response:', parseError);
      }
    }

    // Enhanced fallback
    const fallbackRecommendations = [
      {
        type: 'follow_up_call',
        priority: contextData.contact ? 'high' : 'medium',
        title: `Follow up with ${contextData.contact?.first_name || 'contact'}`,
        description: 'Schedule a call to discuss next steps and address any questions',
        suggestedDate: new Date(Date.now() + 2 * 24 * 60 * 60 * 1000).toISOString(),
        reasoning: 'Maintaining engagement momentum is crucial for conversion',
        estimatedDuration: '30 minutes'
      },
      {
        type: 'send_proposal',
        priority: 'medium',
        title: 'Prepare custom proposal',
        description: 'Create tailored proposal based on discussed requirements',
        suggestedDate: new Date(Date.now() + 3 * 24 * 60 * 60 * 1000).toISOString(),
        reasoning: 'Customer has shown qualified interest',
        estimatedDuration: '2 hours'
      }
    ];

    return new Response(JSON.stringify({
      recommendations: fallbackRecommendations,
      generatedAt: new Date().toISOString()
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (error) {
    console.error('Error in ai-activity-recommendations:', error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
