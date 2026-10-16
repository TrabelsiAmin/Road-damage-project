insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('public-photos', 'public-photos', true, 307200, array['image/webp','image/jpeg'])
on conflict (id) do nothing;

create policy anon_upload_public_photos on storage.objects
  for insert to anon
  with check (bucket_id = 'public-photos'
              and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.(webp|jpg)$');

create policy authority_delete_public_photos on storage.objects
  for delete to authenticated
  using (bucket_id = 'public-photos' and public.is_authority());

create policy anon_select_public_photo_media on public.media_files
  for select to anon
  using (bucket = 'public-photos');