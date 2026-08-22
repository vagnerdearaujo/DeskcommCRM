"use client";
import { useInfiniteQuery } from "@tanstack/react-query";
import { apiClient } from "@/lib/api/client";
import { showApiError } from "@/components/feedback/ApiErrorToast";
import type { Contact } from "@/lib/types/contacts";
import type { ContactOrderBy } from "@/lib/schemas/contacts";

interface ListResponse {
  data: Contact[];
  meta?: { cursor?: string; has_more?: boolean };
}

export interface ContactListFilters {
  search?: string;
  tag?: string;
  source?: string;
  exclude_source?: string;
  order_by?: ContactOrderBy;
  order_dir?: "asc" | "desc";
  limit?: number;
}

export function useContactList(filters: ContactListFilters) {
  return useInfiniteQuery({
    queryKey: ["contacts", filters],
    initialPageParam: undefined as string | undefined,
    queryFn: async ({ pageParam }) => {
      const qs = new URLSearchParams();
      if (filters.search) qs.set("search", filters.search);
      if (filters.tag) qs.set("tag", filters.tag);
      if (filters.source) qs.set("source", filters.source);
      if (filters.exclude_source) qs.set("exclude_source", filters.exclude_source);
      if (filters.order_by) qs.set("order_by", filters.order_by);
      if (filters.order_dir) qs.set("order_dir", filters.order_dir);
      if (filters.limit) qs.set("limit", String(filters.limit));
      if (pageParam) qs.set("cursor", pageParam);
      try {
        return await apiClient.get<ListResponse>(`/api/v1/contacts?${qs.toString()}`);
      } catch (err) {
        showApiError(err);
        throw err;
      }
    },
    getNextPageParam: (lastPage) =>
      lastPage.meta?.has_more ? lastPage.meta.cursor : undefined,
  });
}