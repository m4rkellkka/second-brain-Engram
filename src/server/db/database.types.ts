export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

export type Database = {
  public: {
    Tables: {
      ai_calls: {
        Row: {
          cache_read_tokens: number;
          capture_id: string | null;
          cost_usd: number;
          created_at: string;
          duration_ms: number;
          id: string;
          input_tokens: number;
          model: string;
          ok: boolean;
          output_tokens: number;
          step: string;
          user_id: string;
        };
        ComputedFields: never;
        Insert: {
          cache_read_tokens?: number;
          capture_id?: string | null;
          cost_usd?: number;
          created_at?: string;
          duration_ms: number;
          id?: string;
          input_tokens?: number;
          model: string;
          ok: boolean;
          output_tokens?: number;
          step: string;
          user_id: string;
        };
        Update: {
          cache_read_tokens?: number;
          capture_id?: string | null;
          cost_usd?: number;
          created_at?: string;
          duration_ms?: number;
          id?: string;
          input_tokens?: number;
          model?: string;
          ok?: boolean;
          output_tokens?: number;
          step?: string;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "ai_calls_capture_id_user_id_fkey";
            columns: ["capture_id", "user_id"];
            isOneToOne: false;
            referencedRelation: "captures";
            referencedColumns: ["id", "user_id"];
          },
        ];
      };
      captures: {
        Row: {
          attempts: number;
          audio_path: string | null;
          claimed_at: string | null;
          created_at: string;
          error: string | null;
          id: string;
          processed_at: string | null;
          raw_text: string | null;
          source: Database["public"]["Enums"]["capture_source"];
          status: Database["public"]["Enums"]["processing_status"];
          timezone: string | null;
          user_id: string;
        };
        ComputedFields: never;
        Insert: {
          attempts?: number;
          audio_path?: string | null;
          claimed_at?: string | null;
          created_at?: string;
          error?: string | null;
          id?: string;
          processed_at?: string | null;
          raw_text?: string | null;
          source: Database["public"]["Enums"]["capture_source"];
          status?: Database["public"]["Enums"]["processing_status"];
          timezone?: string | null;
          user_id: string;
        };
        Update: {
          attempts?: number;
          audio_path?: string | null;
          claimed_at?: string | null;
          created_at?: string;
          error?: string | null;
          id?: string;
          processed_at?: string | null;
          raw_text?: string | null;
          source?: Database["public"]["Enums"]["capture_source"];
          status?: Database["public"]["Enums"]["processing_status"];
          timezone?: string | null;
          user_id?: string;
        };
        Relationships: [];
      };
      entries: {
        Row: {
          capture_id: string | null;
          confidence: number | null;
          content: string;
          created_at: string;
          done_at: string | null;
          due_at: string | null;
          embedding: string | null;
          id: string;
          kind: Database["public"]["Enums"]["entry_kind"];
          needs_review: boolean;
          project_id: string | null;
          suggested_project_name: string | null;
          updated_at: string;
          url: string | null;
          user_id: string;
        };
        ComputedFields: never;
        Insert: {
          capture_id?: string | null;
          confidence?: number | null;
          content: string;
          created_at?: string;
          done_at?: string | null;
          due_at?: string | null;
          embedding?: string | null;
          id?: string;
          kind: Database["public"]["Enums"]["entry_kind"];
          needs_review?: boolean;
          project_id?: string | null;
          suggested_project_name?: string | null;
          updated_at?: string;
          url?: string | null;
          user_id: string;
        };
        Update: {
          capture_id?: string | null;
          confidence?: number | null;
          content?: string;
          created_at?: string;
          done_at?: string | null;
          due_at?: string | null;
          embedding?: string | null;
          id?: string;
          kind?: Database["public"]["Enums"]["entry_kind"];
          needs_review?: boolean;
          project_id?: string | null;
          suggested_project_name?: string | null;
          updated_at?: string;
          url?: string | null;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "entries_capture_id_user_id_fkey";
            columns: ["capture_id", "user_id"];
            isOneToOne: false;
            referencedRelation: "captures";
            referencedColumns: ["id", "user_id"];
          },
          {
            foreignKeyName: "entries_project_id_user_id_fkey";
            columns: ["project_id", "user_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id", "user_id"];
          },
        ];
      };
      entry_corrections: {
        Row: {
          created_at: string;
          entry_id: string;
          field: string;
          from_value: string | null;
          id: string;
          to_value: string | null;
          user_id: string;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          entry_id: string;
          field: string;
          from_value?: string | null;
          id?: string;
          to_value?: string | null;
          user_id: string;
        };
        Update: {
          created_at?: string;
          entry_id?: string;
          field?: string;
          from_value?: string | null;
          id?: string;
          to_value?: string | null;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "entry_corrections_entry_id_user_id_fkey";
            columns: ["entry_id", "user_id"];
            isOneToOne: false;
            referencedRelation: "entries";
            referencedColumns: ["id", "user_id"];
          },
        ];
      };
      entry_links: {
        Row: {
          kind: Database["public"]["Enums"]["link_kind"];
          source_id: string;
          target_id: string;
          user_id: string;
          weight: number | null;
        };
        ComputedFields: never;
        Insert: {
          kind: Database["public"]["Enums"]["link_kind"];
          source_id: string;
          target_id: string;
          user_id: string;
          weight?: number | null;
        };
        Update: {
          kind?: Database["public"]["Enums"]["link_kind"];
          source_id?: string;
          target_id?: string;
          user_id?: string;
          weight?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "entry_links_source_id_user_id_fkey";
            columns: ["source_id", "user_id"];
            isOneToOne: false;
            referencedRelation: "entries";
            referencedColumns: ["id", "user_id"];
          },
          {
            foreignKeyName: "entry_links_target_id_user_id_fkey";
            columns: ["target_id", "user_id"];
            isOneToOne: false;
            referencedRelation: "entries";
            referencedColumns: ["id", "user_id"];
          },
        ];
      };
      project_context_items: {
        Row: {
          created_at: string;
          entry_ids: string[];
          id: string;
          project_id: string;
          section: string;
          source: string;
          text: string;
          updated_at: string;
          user_id: string;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          entry_ids?: string[];
          id?: string;
          project_id: string;
          section: string;
          source: string;
          text: string;
          updated_at?: string;
          user_id: string;
        };
        Update: {
          created_at?: string;
          entry_ids?: string[];
          id?: string;
          project_id?: string;
          section?: string;
          source?: string;
          text?: string;
          updated_at?: string;
          user_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "project_context_items_project_id_user_id_fkey";
            columns: ["project_id", "user_id"];
            isOneToOne: false;
            referencedRelation: "projects";
            referencedColumns: ["id", "user_id"];
          },
        ];
      };
      projects: {
        Row: {
          archived_at: string | null;
          color: string;
          context_updated_at: string | null;
          created_at: string;
          id: string;
          name: string;
          slug: string;
          status: string | null;
          status_source: string;
          summary: string | null;
          summary_entry_ids: string[];
          summary_source: string;
          user_id: string;
        };
        ComputedFields: never;
        Insert: {
          archived_at?: string | null;
          color: string;
          context_updated_at?: string | null;
          created_at?: string;
          id?: string;
          name: string;
          slug: string;
          status?: string | null;
          status_source?: string;
          summary?: string | null;
          summary_entry_ids?: string[];
          summary_source?: string;
          user_id: string;
        };
        Update: {
          archived_at?: string | null;
          color?: string;
          context_updated_at?: string | null;
          created_at?: string;
          id?: string;
          name?: string;
          slug?: string;
          status?: string | null;
          status_source?: string;
          summary?: string | null;
          summary_entry_ids?: string[];
          summary_source?: string;
          user_id?: string;
        };
        Relationships: [];
      };
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      apply_context_patch: {
        Args: {
          entry_ids?: string[];
          items?: Json;
          new_status?: string;
          new_summary?: string;
          project_id: string;
        };
        Returns: undefined;
      };
      apply_sorted_capture: {
        Args: { capture_id: string; rows: Json };
        Returns: {
          capture_id: string | null;
          confidence: number | null;
          content: string;
          created_at: string;
          done_at: string | null;
          due_at: string | null;
          embedding: string | null;
          id: string;
          kind: Database["public"]["Enums"]["entry_kind"];
          needs_review: boolean;
          project_id: string | null;
          suggested_project_name: string | null;
          updated_at: string;
          url: string | null;
          user_id: string;
        }[];
        SetofOptions: {
          from: "*";
          to: "entries";
          isOneToOne: false;
          isSetofReturn: true;
        };
      };
      claim_capture: {
        Args: { capture_id: string; max_attempts?: number };
        Returns: {
          attempts: number;
          audio_path: string | null;
          claimed_at: string | null;
          created_at: string;
          error: string | null;
          id: string;
          processed_at: string | null;
          raw_text: string | null;
          source: Database["public"]["Enums"]["capture_source"];
          status: Database["public"]["Enums"]["processing_status"];
          timezone: string | null;
          user_id: string;
        };
        SetofOptions: {
          from: "*";
          to: "captures";
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      create_text_capture: {
        Args: { content: string; timezone?: string };
        Returns: {
          attempts: number;
          audio_path: string | null;
          claimed_at: string | null;
          created_at: string;
          error: string | null;
          id: string;
          processed_at: string | null;
          raw_text: string | null;
          source: Database["public"]["Enums"]["capture_source"];
          status: Database["public"]["Enums"]["processing_status"];
          timezone: string | null;
          user_id: string;
        };
        SetofOptions: {
          from: "*";
          to: "captures";
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      fail_capture: {
        Args: { capture_id: string; max_attempts?: number; message: string };
        Returns: {
          attempts: number;
          audio_path: string | null;
          claimed_at: string | null;
          created_at: string;
          error: string | null;
          id: string;
          processed_at: string | null;
          raw_text: string | null;
          source: Database["public"]["Enums"]["capture_source"];
          status: Database["public"]["Enums"]["processing_status"];
          timezone: string | null;
          user_id: string;
        };
        SetofOptions: {
          from: "*";
          to: "captures";
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
    };
    Enums: {
      capture_source: "text" | "voice";
      entry_kind: "idea" | "task" | "note" | "link";
      link_kind: "semantic" | "manual";
      processing_status: "pending" | "processing" | "processed" | "failed";
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
};

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">;

type DefaultSchema = DatabaseWithoutInternals[Extract<
  keyof Database,
  "public"
>];

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R;
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R;
      }
      ? R
      : never
    : never;

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema["Tables"] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I;
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I;
      }
      ? I
      : never
    : never;

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema["Tables"] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U;
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U;
      }
      ? U
      : never
    : never;

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    keyof DefaultSchema["Enums"] | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never;

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never;

export const Constants = {
  public: {
    Enums: {
      capture_source: ["text", "voice"],
      entry_kind: ["idea", "task", "note", "link"],
      link_kind: ["semantic", "manual"],
      processing_status: ["pending", "processing", "processed", "failed"],
    },
  },
} as const;
