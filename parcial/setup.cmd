@echo off
REM parcial\setup.cmd (for Windows PowerShell/CMD)

echo.
echo 🔧 Setting up ParcialRuby...
echo.

REM Check if Ruby is installed
ruby --version >nul 2>&1
if errorlevel 1 (
    echo ❌ Ruby is not installed or not in PATH
    exit /b 1
)

echo ✅ Ruby found

REM Install bundler if needed
echo 📦 Installing Bundler...
gem install bundler --quiet

REM Install gems
echo 📦 Installing gems from Gemfile.simple...
bundler install --gemfile Gemfile.simple

REM Create public directory
if not exist "public" mkdir public

echo.
echo ✅ Setup complete!
echo.
echo To start the server:
echo   bundle exec ruby app.rb
echo.
echo Server will run on http://localhost:3000
echo.

pause
