# 📱 AI-Powered Todo & Team Management App

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)](https://flutter.dev/)
[![Firebase](https://img.shields.io/badge/Firebase-039BE5?style=for-the-badge&logo=Firebase&logoColor=white)](https://firebase.google.com/)
[![SQLite](https://img.shields.io/badge/sqlite-%2307405e.svg?style=for-the-badge&logo=sqlite&logoColor=white)](https://www.sqlite.org/)
[![Gemini API](https://img.shields.io/badge/Gemini%20API-8E75B2?style=for-the-badge&logo=googlebard&logoColor=white)](https://ai.google.dev/)

> A full-featured productivity app combining **personal task management**, **team collaboration**, and **AI-powered automation**.

## 🚀 Overview

This project is a cross-platform Todo application built with Flutter that goes beyond basic task management. The goal is to provide a smart productivity system that works seamlessly both offline and online.

It integrates:
* 📌 **Personal task tracking**
* 👥 **Team collaboration** (groups, roles, shared tasks)
* 🤖 **AI assistant (Gemini)** for automation
* 🔄 **Offline-first architecture** with cloud synchronization

---

## 🧠 Key Highlights

* **Hybrid Database:** Seamless integration of SQLite and Firebase Firestore.
* **Offline-first Design:** Automatic cloud sync when the connection is restored.
* **AI-Powered Automation:** Create, update, and manage tasks using natural language.
* **Real-time Collaboration:** Group chat and shared workspaces.
* **Advanced Notifications:** Exact alarms, snoozing, and actionable push notifications.

---

## 🗄️ Architecture: Hybrid Database System

| 📱 Local (SQLite) | ☁️ Cloud (Firestore) |
| :--- | :--- |
| **Purpose:** Stores tasks when offline for zero-latency usage. | **Purpose:** Syncs data when the user logs in for backup and multi-device access. |
| **Fields:** `title`, `description`, `datetime`, `repeat`, `reminder`, etc. | **Collections:** <br> - `users` (profile, friends, hidden tasks)<br> - `groups` (members, roles, tasks, messages) |

👉 **Benefits:** Ensures fast offline usage, reliable cloud backups, and smooth multi-device synchronization.

---

## ✨ Features Breakdown

### 👤 Authentication & Social
* [x] Email / Password login (with email verification).
* [x] Google Sign-In & Phone OTP login.
* [x] Add friends via exact email or phone number.
* [x] Two-way friendship system.

### ✅ Task Management
* [x] **Smart Views:** Inbox (all tasks), Today, and Upcoming (Calendar view).
* [x] **Reminders & Repeating:** Set reminders before deadline and repeat modes (Daily/Weekly).
* [x] **Swipe Actions:** Quickly Complete or Archive tasks with Undo support.

### 👥 Group Collaboration & Chat
* [x] **Workspaces:** Create or join groups via a 6-character invite code.
* [x] **Role System:** Admin, Co-admin, and Member permissions.
* [x] **Shared Tasks:** Manage group tasks (can be hidden from the personal view).
* [x] **Real-time Chat:** Group messaging with system alerts (join/leave/AI actions) and a Mute feature.

### 🤖 AI Assistant (Gemini Integration)
* [x] **Context-Aware:** The AI knows if you are in a personal space or a specific group.
* [x] **Chat-to-Action Automation:**
    * *“Create a meeting tomorrow at 9 AM”* -> Auto-creates task.
    * *“Delete all completed tasks”* -> Bulk deletes with undo option.
    * Reschedule or edit tasks via natural conversation.

### 🔔 Advanced Notification System
* [x] Exact scheduled push notifications.
* [x] Repeat notifications (Daily/Weekly) & Pre-task reminders.
* [x] **Quick Actions:** Mark as *Done* or *Snooze* directly from the notification banner.

---

## 🛠️ Technologies Used

* **Framework:** Flutter (Dart)
* **Backend & Auth:** Firebase Firestore, Firebase Auth
* **Local DB:** SQLite (`sqflite`)
* **AI Integration:** Google Gemini API
* **Core Packages:** `flutter_local_notifications`, `timezone`, `table_calendar`

---

## 🎯 Future Improvements

* [ ] Improve UI/UX design & animations.
* [ ] Add robust conflict handling for cloud synchronization.
* [ ] Voice command integration with AI.
* [ ] Web version support.
* [ ] Advanced analytics and productivity dashboard.

---

## 👨‍💻 Author

**Nguyễn Quốc Trọng**
* GitHub: [DevTrongVN](https://github.com/DevTrongVN)
