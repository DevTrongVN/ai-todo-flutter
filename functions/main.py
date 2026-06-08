from firebase_functions import firestore_fn
from firebase_admin import initialize_app, messaging, firestore

initialize_app()

# ================= 1. BẮN THÔNG BÁO TIN NHẮN NHÓM =================
@firestore_fn.on_document_created(document="groups/{groupId}/messages/{messageId}")
def notify_new_message(event: firestore_fn.Event[firestore_fn.DocumentSnapshot | None]) -> None:
    if event.data is None: return
    db = firestore.client()
    message = event.data.to_dict()
    group_id = event.params["groupId"]
    is_system = message.get("isSystem", False)
    text = message.get("text", "")
    sender_name = message.get("senderName", "Ai đó")

    group_name = "Tin nhắn nhóm"
    group_doc = db.collection("groups").document(group_id).get()
    if group_doc.exists:
        group_name = group_doc.to_dict().get("name", "Tin nhắn nhóm")

    body_text = text if is_system else f"{sender_name}: {text}"

    msg = messaging.Message(
        notification=messaging.Notification(title=group_name, body=body_text),
        data={"type": "chat", "groupId": str(group_id), "tabIndex": "0"},
        topic=f"group_{group_id}"
    )
    try: messaging.send(msg)
    except Exception as e: print(f"Lỗi: {e}")

# ================= 2. BẮN THÔNG BÁO LỊCH NHÓM =================
@firestore_fn.on_document_created(document="groups/{groupId}/tasks/{taskId}")
def notify_new_group_task(event: firestore_fn.Event[firestore_fn.DocumentSnapshot | None]) -> None:
    if event.data is None: return
    db = firestore.client()
    task = event.data.to_dict()
    group_id = event.params["groupId"]
    task_id = event.params["taskId"]

    group_name = "Lịch nhóm mới"
    group_doc = db.collection("groups").document(group_id).get()
    if group_doc.exists:
        group_name = f"Lịch mới: {group_doc.to_dict().get('name', 'Nhóm')}"

    msg = messaging.Message(
        notification=messaging.Notification(title=group_name, body=f"{task.get('createdBy', 'Ai đó')} vừa thêm: {task.get('title', '')}"),
        data={"type": "task", "groupId": str(group_id), "tabIndex": "1", "taskId": str(task_id)},
        topic=f"group_{group_id}"
    )
    try: messaging.send(msg)
    except Exception as e: print(f"Lỗi: {e}")

# ================= 3. BẮN THÔNG BÁO KẾT BẠN =================
@firestore_fn.on_document_created(document="notifications/{notificationId}")
def notify_friend_request(event: firestore_fn.Event[firestore_fn.DocumentSnapshot | None]) -> None:
    if event.data is None: return
    noti_data = event.data.to_dict()
    target_uid = noti_data.get("targetUid")
    title = noti_data.get("title", "Thông báo")
    body = noti_data.get("body", "")

    msg = messaging.Message(
        notification=messaging.Notification(title=title, body=body),
        data={"type": "friend_request"},
        topic=f"user_{target_uid}"
    )
    try: messaging.send(msg)
    except Exception as e: print(f"Lỗi: {e}")

# ================= 4. BẮN THÔNG BÁO CHAT CÁ NHÂN =================
@firestore_fn.on_document_created(document="private_chats/{chatId}/messages/{messageId}")
def notify_private_message(event: firestore_fn.Event[firestore_fn.DocumentSnapshot | None]) -> None:
    if event.data is None: return

    message = event.data.to_dict()
    chat_id = event.params["chatId"]

    sender_id = message.get("senderId", "")
    sender_name = message.get("senderName", "Ai đó")
    text = message.get("text", "")

    uids = chat_id.split("_")
    if len(uids) == 2:
        target_uid = uids[1] if uids[0] == sender_id else uids[0]

        msg = messaging.Message(
            notification=messaging.Notification(title=sender_name, body=text),
            data={
                "type": "private_chat",
                "chatId": chat_id,
                "targetUid": sender_id,
                "targetName": sender_name
            },
            topic=f"user_{target_uid}"
        )
        try: messaging.send(msg)
        except Exception as e: print(f"Lỗi: {e}")