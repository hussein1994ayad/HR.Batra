/** Supabase Storage bucket that holds each `deleted_files.file_type`. */
export const BUCKET_BY_TYPE: Record<string, string> = {
  avatar: 'avatars',
  document: 'employee-documents',
  pledge: 'loan-pledges',
  logo: 'company-logos',
};

export function bucketFor(fileType: string): string {
  return BUCKET_BY_TYPE[fileType] ?? 'employee-documents';
}
