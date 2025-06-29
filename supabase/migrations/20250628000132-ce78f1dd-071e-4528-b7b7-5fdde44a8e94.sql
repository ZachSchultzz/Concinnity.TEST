
-- Enhance the files table content structure for better spreadsheet support
ALTER TABLE public.files 
ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}';

-- Create a dedicated table for spreadsheet cell changes for real-time collaboration
CREATE TABLE IF NOT EXISTS public.spreadsheet_operations (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  file_id UUID REFERENCES public.files ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES auth.users NOT NULL,
  operation_type TEXT NOT NULL CHECK (operation_type IN ('cell_update', 'sheet_add', 'sheet_delete', 'sheet_rename', 'format_change')),
  sheet_id TEXT NOT NULL,
  cell_reference TEXT, -- e.g., "A1", "B2:C5" for ranges
  operation_data JSONB NOT NULL,
  timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  sequence_number BIGSERIAL
);

-- Create index for faster real-time queries
CREATE INDEX IF NOT EXISTS idx_spreadsheet_operations_file_timestamp 
ON public.spreadsheet_operations(file_id, timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_spreadsheet_operations_sequence 
ON public.spreadsheet_operations(file_id, sequence_number DESC);

-- Enable RLS on spreadsheet_operations
ALTER TABLE public.spreadsheet_operations ENABLE ROW LEVEL SECURITY;

-- RLS policies for spreadsheet_operations
CREATE POLICY "Users can view operations on files they have access to" 
  ON public.spreadsheet_operations FOR SELECT 
  USING (
    file_id IN (
      SELECT id FROM public.files WHERE user_id = auth.uid()
      UNION
      SELECT file_id FROM public.file_shares WHERE shared_with_user_id = auth.uid()
    )
  );

CREATE POLICY "Users can create operations on files they have access to" 
  ON public.spreadsheet_operations FOR INSERT 
  WITH CHECK (
    user_id = auth.uid() AND
    file_id IN (
      SELECT id FROM public.files WHERE user_id = auth.uid()
      UNION
      SELECT file_id FROM public.file_shares WHERE shared_with_user_id = auth.uid() AND permission IN ('edit', 'admin')
    )
  );

-- Enable realtime for spreadsheet operations
ALTER TABLE public.spreadsheet_operations REPLICA IDENTITY FULL;
ALTER PUBLICATION supabase_realtime ADD TABLE public.spreadsheet_operations;

-- Create a function to get the latest spreadsheet state
CREATE OR REPLACE FUNCTION public.get_spreadsheet_state(p_file_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result JSONB;
BEGIN
  -- Get the base content from files table
  SELECT content INTO result FROM public.files WHERE id = p_file_id;
  
  -- If no content, return empty sheets structure
  IF result IS NULL THEN
    result := '{"sheets": [{"id": "sheet1", "name": "Sheet1", "data": {}}], "activeSheetId": "sheet1"}';
  END IF;
  
  RETURN result;
END;
$$;

-- Create a function to apply spreadsheet operations
CREATE OR REPLACE FUNCTION public.apply_spreadsheet_operation(
  p_file_id UUID,
  p_user_id UUID,
  p_operation_type TEXT,
  p_sheet_id TEXT,
  p_cell_reference TEXT DEFAULT NULL,
  p_operation_data JSONB DEFAULT '{}'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  operation_id UUID;
  current_content JSONB;
  updated_content JSONB;
BEGIN
  -- Insert the operation record
  INSERT INTO public.spreadsheet_operations (
    file_id, user_id, operation_type, sheet_id, cell_reference, operation_data
  ) VALUES (
    p_file_id, p_user_id, p_operation_type, p_sheet_id, p_cell_reference, p_operation_data
  ) RETURNING id INTO operation_id;
  
  -- Get current file content
  SELECT content INTO current_content FROM public.files WHERE id = p_file_id;
  
  -- Apply the operation to update the file content
  -- This is a simplified version - in production you'd want more sophisticated merging
  IF p_operation_type = 'cell_update' THEN
    -- Update cell data in the content
    updated_content := current_content;
    -- Note: This would require more complex JSONB manipulation in a real implementation
  END IF;
  
  -- Update the file with new content and increment version
  UPDATE public.files 
  SET 
    content = COALESCE(updated_content, current_content),
    updated_at = now()
  WHERE id = p_file_id;
  
  RETURN operation_id;
END;
$$;
