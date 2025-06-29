
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
    const { businessId } = await req.json();
    
    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    
    // Mock insights for demonstration
    const mockInsights = [
      {
        id: 'insight-1',
        type: 'trend',
        title: 'Sales Velocity Increasing',
        description: 'Your average deal closure time has decreased by 15% this month, indicating improved sales efficiency.',
        impact: 'high',
        data: { velocity: '+15%', period: 'this month' },
        createdAt: new Date()
      },
      {
        id: 'insight-2',
        type: 'prediction',
        title: 'Q4 Revenue Forecast',
        description: 'Based on current pipeline, you\'re on track to exceed Q4 revenue targets by 8%.',
        impact: 'high',
        data: { forecast: '+8%', confidence: '87%' },
        createdAt: new Date()
      },
      {
        id: 'insight-3',
        type: 'recommendation',
        title: 'Follow-up Opportunity',
        description: '12 leads have been inactive for over 14 days. Consider a re-engagement campaign.',
        impact: 'medium',
        data: { inactiveLeads: 12, days: 14 },
        createdAt: new Date()
      },
      {
        id: 'insight-4',
        type: 'alert',
        title: 'Deal Risk Alert',
        description: '3 high-value deals in your pipeline show signs of stalling. Immediate action recommended.',
        impact: 'high',
        data: { stalledDeals: 3, value: '$45,000' },
        createdAt: new Date()
      }
    ];

    // In production, this would analyze real CRM data using OpenAI
    if (openAIApiKey) {
      console.log('OpenAI analysis would be performed here with CRM metrics');
    }

    return new Response(JSON.stringify({ 
      insights: mockInsights,
      generatedAt: new Date().toISOString()
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('Error in ai-dashboard-insights:', error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
