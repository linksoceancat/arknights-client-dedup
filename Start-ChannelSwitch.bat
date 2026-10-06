@echo off
chcp 65001 >nul
title Arknights Channel Switch
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ArknightsChannelSwitch.ps1"
