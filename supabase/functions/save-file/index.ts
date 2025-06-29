
import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      { auth: { persistSession: false } }
    );

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) throw new Error("No authorization header provided");

    const token = authHeader.replace("Bearer ", "");
    const { data: userData, error: userError } = await supabaseClient.auth.getUser(token);
    if (userError) throw new Error(`Authentication error: ${userError.message}`);
    
    const user = userData.user;
    if (!user) throw new Error("User not authenticated");

    const { fileId, name, content, type } = await req.json();

    let result;
    
    if (fileId) {
      // Update existing file
      const { data: existingFile } = await supabaseClient
        .from('files')
        .select('version, content')
        .eq('id', fileId)
        .eq('user_id', user.id)
        .single();

      if (existingFile && existingFile.content !== content) {
        // Save current version to history
        await supabaseClient.from('file_versions').insert({
          file_id: fileId,
          version_number: existingFile.version,
          content: existingFile.content,
          created_by: user.id,
          change_summary: 'Auto-save version'
        });

        // Update file with new content and increment version
        result = await supabaseClient
          .from('files')
          .update({
            name,
            content,
            version: existingFile.version + 1,
            file_size: content ? content.length : 0,
            updated_at: new Date().toISOString()
          })
          .eq('id', fileId)
          .eq('user_id', user.id)
          .select()
          .single();
      } else {
        // Just update metadata without version change
        result = await supabaseClient
          .from('files')
          .update({
            name,
            updated_at: new Date().toISOString()
          })
          .eq('id', fileId)
          .eq('user_id', user.id)
          .select()
          .single();
      }
    } else {
      // Create new file
      result = await supabaseClient
        .from('files')
        .insert({
          user_id: user.id,
          name,
          content,
          type,
          file_size: content ? content.length : 0,
          url: `/${type}/${Date.now()}`
        })
        .select()
        .single();
    }

    if (result.error) throw result.error;

    return new Response(JSON.stringify({ 
      success: true, 
      file: result.data 
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error) {
    console.error('Save file error:', error);
    return new Response(JSON.stringify({ 
      error: error instanceof Error ? error.message : 'Unknown error' 
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});
