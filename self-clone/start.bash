@echo off
echo Building Roblox Game Architecture...

:: Root Directories
mkdir src\ReplicatedStorage
mkdir src\ServerScriptService
mkdir src\ServerStorage
mkdir src\StarterPlayer\StarterPlayerScripts
mkdir src\StarterGui
mkdir src\Workspace

:: ReplicatedStorage structure
mkdir src\ReplicatedStorage\Shared\Constants
mkdir src\ReplicatedStorage\Shared\Enums
mkdir src\ReplicatedStorage\Shared\Utilities
mkdir src\ReplicatedStorage\Shared\Classes
mkdir src\ReplicatedStorage\Network\Events
mkdir src\ReplicatedStorage\Network\Functions
mkdir src\ReplicatedStorage\Components
mkdir src\ReplicatedStorage\Assets\Models
mkdir src\ReplicatedStorage\Assets\UI
mkdir src\ReplicatedStorage\Assets\Effects
mkdir src\ReplicatedStorage\Assets\Animations

:: ServerScriptService structure
mkdir src\ServerScriptService\Server\Services
mkdir src\ServerScriptService\Server\Components
mkdir src\ServerScriptService\Server\Data
mkdir src\ServerScriptService\Server\Core

:: ServerStorage structure
mkdir src\ServerStorage\MapChunks
mkdir src\ServerStorage\ServerAssets
mkdir src\ServerStorage\Bindables

:: StarterPlayerScripts structure
mkdir src\StarterPlayer\StarterPlayerScripts\Client\Controllers
mkdir src\StarterPlayer\StarterPlayerScripts\Client\Components
mkdir src\StarterPlayer\StarterPlayerScripts\Client\Core

:: StarterGui structure
mkdir src\StarterGui\HUD
mkdir src\StarterGui\Menus
mkdir src\StarterGui\Overlays
mkdir src\StarterGui\Loading

:: Workspace structure
mkdir src\Workspace\Map
mkdir src\Workspace\Spawns
mkdir src\Workspace\Entities
mkdir src\Workspace\ActiveMinions

echo Architecture generation complete!
pause