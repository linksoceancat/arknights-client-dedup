@echo off
chcp 65001 >nul
title Arknights Client Dedup
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ArknightsDedup.ps1"
