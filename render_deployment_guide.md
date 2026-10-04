# Deploying StudyIntelli Backend to Render for Free

I've automatically updated your backend code to meet all of Render's requirements! Here is exactly what was changed:
1. **Added Dependencies**: Added `gunicorn`, `dj-database-url`, and `whitenoise` to your `requirements.txt`.
2. **Updated Settings**: Configured `settings.py` to use `WhiteNoise` for static files, automatically read `DATABASE_URL` for the database connection, and automatically whitelist the Render hostname in `ALLOWED_HOSTS`.
3. **Build Script**: Created a `build.sh` script to automatically install requirements, collect static files, and migrate your database when deploying.

Follow these step-by-step instructions to get your backend live on Render for free.

## Step 1: Push Your Code to GitHub
Render connects directly to your GitHub repository to deploy your code automatically.

1. Create a new repository on [GitHub](https://github.com/new) (you can make it private).
2. Open your terminal in the `StudyIntelli` root folder and run:
   ```bash
   git init
   git add .
   git commit -m "Prepare for Render deployment"
   git branch -M main
   git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPOSITORY.git
   git push -u origin main
   ```
*(Replace the URL with your actual GitHub repository URL)*

## Step 2: Create a PostgreSQL Database on Render
Render offers a free PostgreSQL database that we will use.

1. Go to [Render.com](https://render.com/) and create a free account if you haven't already.
2. In the Render Dashboard, click **New +** and select **PostgreSQL**.
3. Fill in the details:
   - **Name**: `studyintelli-db` (or anything you like)
   - **Database**: `studyintelli_db`
   - **User**: `postgres`
   - **Region**: Choose the one closest to you.
   - **Instance Type**: **Free**
4. Click **Create Database**.
5. Once created, scroll down to the **Connections** section and find the **Internal Database URL** (it looks like `postgres://postgres:password@hostname/studyintelli_db`). Copy this URL.

## Step 3: Create the Web Service on Render
Now we will deploy the Django backend.

1. In the Render Dashboard, click **New +** and select **Web Service**.
2. Connect your GitHub account and select your `StudyIntelli` repository.
3. Fill in the details:
   - **Name**: `studyintelli-api`
   - **Region**: Choose the same region as your database.
   - **Root Directory**: `backend` *(Important: Since your Django app is inside the `backend` folder)*
   - **Environment**: `Python 3`
   - **Build Command**: `./build.sh`
   - **Start Command**: `gunicorn config.wsgi:application`
   - **Instance Type**: **Free**
4. Expand the **Advanced** section and click **Add Environment Variable**. Add the following variables:
   - `PYTHON_VERSION`: `3.10.8` *(Or whichever Python 3 version you are using)*
   - `DATABASE_URL`: Paste the **Internal Database URL** you copied from the previous step.
   - `GROQ_API_KEY`: Paste your Groq API key from your local `.env` file.
   - `SECRET_KEY`: Paste your Django Secret Key from your local `.env` file (or generate a new random string).
5. Click **Create Web Service**.

Render will now build and deploy your app. This may take a few minutes. Once it's live, you'll see a green "Live" status and a URL at the top left (e.g., `https://studyintelli-api.onrender.com`).

## Step 4: Connect Your Flutter Frontend
Your backend is now live on the internet! Let's point your frontend app to this new URL so you don't need to run it locally anymore.

1. Open `frontend/lib/core/api_client.dart`.
2. Update the `_physicalDeviceUrl` and `baseUrl` logic to use your new Render URL:

```dart
// Change your ApiClient class baseUrl to look like this:
class ApiClient {
  // Replace with your actual Render URL
  static const String _productionUrl = 'https://studyintelli-api.onrender.com/api';
  
  static String get baseUrl {
    // You can force it to use the production URL everywhere now!
    return _productionUrl;
  }
  
  // ... rest of the file stays the same
}
```

That's it! Your physical device will now make API calls directly to your Render backend, meaning you don't need to worry about local IP addresses, firewall rules, or keeping your laptop server running.
