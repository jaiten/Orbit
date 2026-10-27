insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('orbit-note-photos','orbit-note-photos',false,2097152,array['image/jpeg'])
on conflict (id) do update set public=false,file_size_limit=2097152,allowed_mime_types=array['image/jpeg'];
create policy orbit_photo_read on storage.objects for select to authenticated
using (bucket_id='orbit-note-photos' and (storage.foldername(name))[1]=(select auth.uid()::text) and (select orbit_private.session_allowed()));
create policy orbit_photo_insert on storage.objects for insert to authenticated
with check (bucket_id='orbit-note-photos' and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.jpg$' and (storage.foldername(name))[1]=(select auth.uid()::text) and (select orbit_private.session_allowed()));
create policy orbit_photo_update on storage.objects for update to authenticated
using (bucket_id='orbit-note-photos' and (storage.foldername(name))[1]=(select auth.uid()::text) and (select orbit_private.session_allowed()))
with check (bucket_id='orbit-note-photos' and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.jpg$' and (storage.foldername(name))[1]=(select auth.uid()::text) and (select orbit_private.session_allowed()));
create policy orbit_photo_delete on storage.objects for delete to authenticated
using (bucket_id='orbit-note-photos' and (storage.foldername(name))[1]=(select auth.uid()::text) and (select orbit_private.session_allowed()));

