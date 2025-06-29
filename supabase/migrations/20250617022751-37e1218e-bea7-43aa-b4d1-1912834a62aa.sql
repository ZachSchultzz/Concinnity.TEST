
-- Create files table for storing documents, spreadsheets, and presentations
CREATE TABLE public.files (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users NOT NULL,
  business_id UUID REFERENCES public.businesses,
  name TEXT NOT NULL,
  content TEXT,
  type TEXT NOT NULL CHECK (type IN ('docs', 'sheets', 'slides')),
  starred BOOLEAN DEFAULT false,
  url TEXT NOT NULL,
  file_size INTEGER DEFAULT 0,
  version INTEGER DEFAULT 1,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create file_versions table for version history
CREATE TABLE public.file_versions (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  file_id UUID REFERENCES public.files ON DELETE CASCADE NOT NULL,
  version_number INTEGER NOT NULL,
  content TEXT,
  created_by UUID REFERENCES auth.users NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  change_summary TEXT
);

-- Create file_shares table for sharing files between users
CREATE TABLE public.file_shares (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  file_id UUID REFERENCES public.files ON DELETE CASCADE NOT NULL,
  shared_with_user_id UUID REFERENCES auth.users NOT NULL,
  shared_by_user_id UUID REFERENCES auth.users NOT NULL,
  permission TEXT NOT NULL CHECK (permission IN ('view', 'edit', 'admin')),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(file_id, shared_with_user_id)
);

-- Create notifications table for system notifications
CREATE TABLE public.notifications (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users NOT NULL,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  read BOOLEAN DEFAULT false,
  data JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create file_comments table for collaboration comments
CREATE TABLE public.file_comments (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  file_id UUID REFERENCES public.files ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES auth.users NOT NULL,
  content TEXT NOT NULL,
  position JSONB, -- stores x, y coordinates for positioned comments
  resolved BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create user_presence table for real-time collaboration
CREATE TABLE public.user_presence (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users NOT NULL,
  file_id UUID REFERENCES public.files ON DELETE CASCADE NOT NULL,
  cursor_position JSONB,
  selection_range JSONB,
  last_seen TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  is_active BOOLEAN DEFAULT true,
  UNIQUE(user_id, file_id)
);

-- Enable Row Level Security
ALTER TABLE public.files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.file_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.file_shares ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.file_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_presence ENABLE ROW LEVEL SECURITY;

-- RLS Policies for files
CREATE POLICY "Users can view their own files or files shared with them" 
  ON public.files FOR SELECT 
  USING (
    user_id = auth.uid() OR 
    id IN (
      SELECT file_id FROM public.file_shares 
      WHERE shared_with_user_id = auth.uid()
    )
  );

CREATE POLICY "Users can create their own files" 
  ON public.files FOR INSERT 
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update their own files or files they have edit access to" 
  ON public.files FOR UPDATE 
  USING (
    user_id = auth.uid() OR 
    id IN (
      SELECT file_id FROM public.file_shares 
      WHERE shared_with_user_id = auth.uid() 
      AND permission IN ('edit', 'admin')
    )
  );

CREATE POLICY "Users can delete their own files" 
  ON public.files FOR DELETE 
  USING (user_id = auth.uid());

-- RLS Policies for file_shares
CREATE POLICY "Users can view shares for their files or files shared with them" 
  ON public.file_shares FOR SELECT 
  USING (
    shared_with_user_id = auth.uid() OR 
    shared_by_user_id = auth.uid() OR
    file_id IN (SELECT id FROM public.files WHERE user_id = auth.uid())
  );

CREATE POLICY "Users can create shares for their own files" 
  ON public.file_shares FOR INSERT 
  WITH CHECK (
    file_id IN (SELECT id FROM public.files WHERE user_id = auth.uid())
  );

CREATE POLICY "Users can delete shares for their own files" 
  ON public.file_shares FOR DELETE 
  USING (
    file_id IN (SELECT id FROM public.files WHERE user_id = auth.uid())
  );

-- RLS Policies for notifications
CREATE POLICY "Users can view their own notifications" 
  ON public.notifications FOR SELECT 
  USING (user_id = auth.uid());

CREATE POLICY "Users can update their own notifications" 
  ON public.notifications FOR UPDATE 
  USING (user_id = auth.uid());

-- RLS Policies for file_comments
CREATE POLICY "Users can view comments on files they have access to" 
  ON public.file_comments FOR SELECT 
  USING (
    file_id IN (
      SELECT id FROM public.files WHERE user_id = auth.uid()
      UNION
      SELECT file_id FROM public.file_shares WHERE shared_with_user_id = auth.uid()
    )
  );

CREATE POLICY "Users can create comments on files they have access to" 
  ON public.file_comments FOR INSERT 
  WITH CHECK (
    user_id = auth.uid() AND
    file_id IN (
      SELECT id FROM public.files WHERE user_id = auth.uid()
      UNION
      SELECT file_id FROM public.file_shares WHERE shared_with_user_id = auth.uid()
    )
  );

-- RLS Policies for user_presence
CREATE POLICY "Users can view presence on files they have access to" 
  ON public.user_presence FOR SELECT 
  USING (
    file_id IN (
      SELECT id FROM public.files WHERE user_id = auth.uid()
      UNION
      SELECT file_id FROM public.file_shares WHERE shared_with_user_id = auth.uid()
    )
  );

CREATE POLICY "Users can update their own presence" 
  ON public.user_presence FOR ALL 
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Enable realtime for collaboration features
ALTER TABLE public.files REPLICA IDENTITY FULL;
ALTER TABLE public.file_comments REPLICA IDENTITY FULL;
ALTER TABLE public.user_presence REPLICA IDENTITY FULL;
ALTER TABLE public.notifications REPLICA IDENTITY FULL;

-- Add tables to realtime publication
ALTER PUBLICATION supabase_realtime ADD TABLE public.files;
ALTER PUBLICATION supabase_realtime ADD TABLE public.file_comments;
ALTER PUBLICATION supabase_realtime ADD TABLE public.user_presence;
ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
