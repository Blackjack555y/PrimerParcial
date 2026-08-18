# parcial/setup.sh (for bash/Linux/macOS)
#!/bin/bash

echo "🔧 Setting up ParcialRuby..."

# Install dependencies
echo "📦 Installing gems..."
bundle install --gemfile Gemfile.simple

# Create public directory if needed
mkdir -p public

echo "✅ Setup complete!"
echo ""
echo "To start the server:"
echo "  bundle exec ruby app.rb"
echo ""
echo "Server will run on http://localhost:3000"
