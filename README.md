# StudyIntelli - Setup and Execution Guide
 
StudyIntelli is a production-ready mobile application that allows students to upload course PDFs and generates prioritized important questions, MCQs, and short/long questions using AI.
 
## 1. Project Structure
 
The repository contains two main directories and one launcher script:
- `backend/`: Python + Django REST Framework API using Clean Architecture concepts.
- `frontend/`: Flutter mobile application using Riverpod for State Management.
- `run_app.ps1`: One-click launcher for Windows (starts the backend and the app for you).
## 2. Prerequisites
 
Install these before running the project (both methods need them):
- **Python 3.10+** (on Windows, tick *"Add python.exe to PATH"* during installation)
- **Flutter SDK 3.0+** (with `flutter` on your PATH)
- **PostgreSQL** database running locally or remotely, with a database named `studyintelli_db`
- **Android SDK platform-tools** (`adb`) if you test on a physical Android device
- **Groq API Key** (get one at [https://console.groq.com/](https://console.groq.com/))
Before the first run, create/edit the `.env` file in the `backend/` directory:
```env
GROQ_API_KEY=your_groq_api_key_here
DB_NAME=studyintelli_db
DB_USER=postgres
DB_PASSWORD=your_postgres_password
DB_HOST=127.0.0.1
DB_PORT=5432
```
 
## 3. Two Ways to Run the Project
 
You can start StudyIntelli in either of two ways. Both give the same result.
 
| | **Option A - Automated** (`run_app.ps1`) | **Option B - Manual** (step by step) |
|---|---|---|
| Best for | Daily development on Windows | First-time understanding, Mac/Linux, debugging |
| Effort | One command | Several commands in several terminals |
| Platform | Windows (PowerShell) | Windows, macOS, Linux |
 
---
 
## 4. Option A - Run Automatically with `run_app.ps1` (Windows)
 
### What the script does
When you run it, the script performs every manual step for you, in this order:
 
1. **Python environment**: uses `backend\venv` (creates it and installs the packages if they are missing).
2. **PostgreSQL**: checks the database is reachable (using `DB_HOST` / `DB_PORT` from `.env`) and tries to start the Windows service if it is stopped.
3. **Migrations**: runs `makemigrations` and `migrate`.
4. **Django backend**: starts the server on `0.0.0.0:8000` in its own window and waits until it really answers.
5. **ADB reverse**: runs `adb reverse tcp:8000 tcp:8000` for every connected Android device.
6. **Flutter**: runs `flutter run` in the `frontend/` folder.
### How to use it
1. Place `run_app.ps1` in the project root (the folder that contains `backend/` and `frontend/`).
2. Connect your phone with USB debugging enabled (or start an Android emulator).
3. Open PowerShell in the project root and run:
```powershell
   .\run_app.ps1
```
 
### Optional switches
```powershell
.\run_app.ps1 -SkipMigrations   # faster start when the database schema has not changed
.\run_app.ps1 -NoFlutter        # start and verify only the backend
```
 
### If PowerShell says the script "is not digitally signed"
Windows blocks scripts that were downloaded or copied from the internet. Use one of these:
```powershell
# Unblock just this file (recommended)
Unblock-File .\run_app.ps1
.\run_app.ps1
 

```
 
### Stopping the app
The backend runs in a separate window titled **"StudyIntelli - Django backend"**. Press `Ctrl+C` in that window (or close it) to stop the server.
 
### Troubleshooting the script
- **Django window shows `ModuleNotFoundError`**: the packages are missing from the virtual environment. Re-run the script (it installs them), or follow Option B step 3.
- **"PostgreSQL is NOT reachable"**: start the PostgreSQL service and check `DB_HOST` / `DB_PORT` in `backend\.env`. If the script cannot start the service, run PowerShell as Administrator once.
- **"Migrations failed"**: usually a wrong `DB_NAME`, `DB_USER` or `DB_PASSWORD` in `backend\.env`, or the database does not exist yet.
- **"Port 8000 is busy"**: another program (or an old Django process) is using the port. Close it and run the script again.
- **Phone cannot reach the API**: make sure the phone shows as `device` in `adb devices` (unlock it and accept the USB debugging prompt), then run the script again.
---
 
## 5. Option B - Run Manually (Step by Step)
 
Use this on macOS/Linux, or when you want full control. You need **two terminals**: one for the backend and one for the Flutter app.
 
### 5.1 Backend Setup
 
1. **Navigate to backend directory**:
```bash
   cd backend
```
2. **Create and activate a virtual environment**:
```bash
   python -m venv venv
   # On Windows:
   .\venv\Scripts\activate
   # On Mac/Linux:
   source venv/bin/activate
```
3. **Install dependencies**:
```bash
   pip install django djangorestframework psycopg2-binary python-dotenv PyMuPDF groq djangorestframework-simplejwt django-cors-headers
```
4. **Configure Environment Variables**:
   Edit the `.env` file in the `backend/` directory (see the example in section 2).
5. **Database Setup**:
   Ensure your PostgreSQL instance is running and you have created a database named `studyintelli_db`. Then run migrations:
```bash
   python manage.py makemigrations
   python manage.py migrate
```
6. **Map the port to your physical device (USB only)**:
   Run this single command in a **separate (external) command prompt**, not in the project terminal. It maps the port of your PC to your physical device so both use the same address:
```bash
   adb reverse tcp:8000 tcp:8000
```
   Skip this step if you use an emulator.
7. **Run the backend server** (in the project terminal, with the virtual environment active):
```bash
   python manage.py runserver
   # or, to listen on all network interfaces:
   python manage.py runserver 0.0.0.0:8000
```
   The API will be available at `http://127.0.0.1:8000`.
 
### 5.2 Flutter Frontend Setup
 
1. **Navigate to the frontend directory**:
```bash
   cd frontend
```
2. **Install Flutter packages**:
```bash
   flutter pub get
```
3. **API Configuration**:
   In `frontend/lib/core/api_client.dart`, set `baseUrl` to match how you run the app:
   | How you run the app | `baseUrl` |
   |---|---|
   | Android emulator | `http://10.0.2.2:8000/api` |
   | Physical device over USB with `adb reverse` | `http://127.0.0.1:8000/api` |
   | Physical device on Wi-Fi, iOS simulator, or web | `http://192.168.1.x:8000/api` (your PC's local IP; start Django with `0.0.0.0:8000`) |
4. **Run the application**:
   Start your Android Emulator or iOS Simulator (or connect your phone), then run:
```bash
   flutter run
```
 
> **Note:** Option A (`run_app.ps1`) does not change `baseUrl`. Make sure it matches your setup from the table above before you run the app.
 
---
 
## 6. Usage Guide
1. **Signup/Login**: Create a new account or login.
2. **Upload PDF**: Click the floating action button to select and upload a course PDF.
3. **Wait for AI**: The system will extract text and call the Groq LLM to generate the structured materials.
4. **Review Materials**: Tap on the generated material to see prioritized important questions, MCQs, fill-in-the-blanks, and more!
 