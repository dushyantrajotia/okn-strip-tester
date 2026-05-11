@echo off
cd /d "%~dp0"
npm install --production
npm start
pause
