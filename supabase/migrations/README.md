# Migrations

Use `npm run supabase -- migration new <name>` from the repository root after the schema change is agreed. Review the generated SQL, then apply it to a fresh local database with `npm run supabase -- db reset` and check it with `npm run supabase -- db lint`. Keep domain migrations here; the web repository does not own copies.
