# Hybrid AI Super App — Phase 6–9

এই প্যাকেজটি আপনার দেওয়া FastAPI + Flutter কোডের পরবর্তী backend ধাপগুলো যোগ করে।

## কী যোগ হয়েছে
- **Phase 6 — নিজের API Key:** `PUT /keys`, `GET /keys`, `DELETE /keys/{provider}`। Claude ও Grok key user অনুযায়ী Fernet encryption দিয়ে DB-তে রাখা হয়; key আবার plain text আকারে ফেরত দেওয়া হয় না।
- **Phase 7 — Coding Agent:** `/chat`-এ `coding_agent: true` পাঠালে coding-focused system instruction ব্যবহার করে plan, patch/files, test commands ও risks চাইবে। এটি code নিজে execute করে না।
- **Phase 8 — Admin Panel API:** `/admin/stats`, `/admin/users`, role change ও user delete। Admin role শুধুমাত্র admin endpoint/DB-তে নির্ধারিত হবে।
- **Phase 9 — Public Deployment:** Dockerfile ও Render blueprint দেওয়া হয়েছে।

## গুরুত্বপূর্ণ সীমাবদ্ধতা/সতর্কতা
1. আপনার দেওয়া ফাইলগুলোতে Flutter project-এর `pubspec.yaml`, Android/iOS config এবং hosting details ছিল না। তাই Flutter UI-এর পূর্ণ compile-tested replacement এখানে দাবি করা হচ্ছে না; API backend সম্পূর্ণ করা হয়েছে।
2. পুরোনো DB-তে `users.role` এবং `user_api_keys` schema migration প্রয়োজন হতে পারে। নতুন DB হলে `create_all` টেবিল তৈরি করবে, কিন্তু পুরোনো table-এ নতুন column যোগ করে না। PostgreSQL হলে migration (Alembic) চালান বা backup নিয়ে migration করুন।
3. Production-এ SQLite ব্যবহার করবেন না; persistent PostgreSQL ব্যবহার করুন।
4. `KEY_ENCRYPTION_SECRET` হারালে saved personal API keys decrypt করা যাবে না। এটি backup/secret manager-এ নিরাপদে রাখুন।
5. `JWT_SECRET` ও `KEY_ENCRYPTION_SECRET` আলাদা, শক্তিশালী secret হবে। `.env` GitHub-এ commit করবেন না।
6. Public deployment-এর আগে HTTPS, rate limiting, email verification, password reset, abuse monitoring, database backups ও privacy policy যোগ করা উচিত।
7. Provider model ID, free tier ও quotas পরিবর্তন হতে পারে। Claude/Grok model ID-ও provider account অনুযায়ী যাচাই করুন।

## Local run
```bash
cd backend
python -m venv .venv
# Windows: .venv\Scripts\activate
# macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
# .env values shell/server environment-এ set করুন
uvicorn main:app --reload
```
API docs: `http://127.0.0.1:8000/docs`

Fernet key তৈরি:
```bash
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

## প্রথম Admin তৈরি
সাধারণ registration করে তারপর server shell-এ:
```bash
python -c "from db import SessionLocal, User; d=SessionLocal(); u=d.query(User).filter_by(email='YOUR_EMAIL').first(); assert u; u.role='admin'; d.commit(); d.close()"
```
এটি একবারই করুন; `YOUR_EMAIL` আপনার নিবন্ধিত admin email দিয়ে বদলান। Public registration-এ কাউকে admin বানানোর endpoint নেই।

## API examples
Header: `Authorization: Bearer <login-token>`

Save Claude key:
```http
PUT /keys
Content-Type: application/json

{"provider":"claude","api_key":"YOUR_CLAUDE_KEY"}
```
Save Grok key: একইভাবে `provider` হবে `grok`।

Coding Agent:
```json
{"message":"এই Python ফাইলটি review করে bug fix-এর patch দাও","coding_agent":true,"free_only":false}
```
নিজের Claude/Grok key ব্যবহার করতে `free_only:false` দিতে হবে। Provider নির্বাচিত না থাকলে configured model-এ fallback করবে।

Admin APIs:
- `GET /admin/stats`
- `GET /admin/users`
- `PUT /admin/users/{id}/role?role=admin`
- `DELETE /admin/users/{id}`

## Flutter integration notes
আপনার `main.dart`-এ `/chat` request JSON-এ `coding_agent: true/false` যোগ করুন। Settings screen থেকে `PUT /keys` call করতে হবে; key শুধু input field-এ লিখে পাঠাবেন, local storage বা logs-এ রাখবেন না। Admin screen-এ login user-এর role `admin` হলে `/admin/stats` ও `/admin/users` দেখাবেন। API URL production domain-এ সেট করুন:
```bash
flutter run --dart-define=API_URL=https://YOUR-API-DOMAIN
```
Android production build:
```bash
flutter build apk --release --dart-define=API_URL=https://YOUR-API-DOMAIN
```
