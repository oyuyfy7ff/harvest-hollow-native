# Harvest Hollow Native Android

This is the first offline-native port scaffold for Harvest Hollow. It uses Godot 4 and does not use HTML5, WebView, a server, or VPN.

## Current prototype

The prototype contains a native 3D scene, an offline local save state, basic player movement, farm plots, plant/harvest interaction, and a minimal status display. The original UI redesign work is intentionally out of scope.

## Run locally

Open this folder in Godot 4.7+ and run the main scene. The prototype was checked in headless mode successfully.

## Android status

An Android SDK/export template is not available in this sandbox, so an installable APK has not been produced yet. The Godot project is prepared for Android export once the SDK and export templates are available.

## Next port work

The remaining work is to migrate the original game systems and assets from Three.js/DOM into native Godot equivalents while preserving the original behavior as closely as possible. This is a real port, not a one-click conversion.
