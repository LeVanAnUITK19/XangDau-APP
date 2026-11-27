# Cấu hình thông báo giá bằng Firebase

Ứng dụng đã có phần nhận FCM và backend đã có hàng đợi gửi thông báo. Cần cấu hình Firebase riêng cho môi trường chạy trước khi bật tính năng.

## 1. Tạo Firebase app cho Android

1. Tạo hoặc chọn một Firebase project và bật Firebase Cloud Messaging.
2. Trong Project settings, thêm Android app với package name `vn.giaxang.gia_xang_dau`.
3. Lấy các giá trị `API key`, `App ID`, `Sender ID` và `Project ID` trong Project settings → General.
4. Trong Android Studio, mở cấu hình chạy Flutter và thêm các tham số sau vào **Additional run args**:

```text
--dart-define=FIREBASE_API_KEY=<API key>
--dart-define=FIREBASE_APP_ID=<App ID>
--dart-define=FIREBASE_MESSAGING_SENDER_ID=<Sender ID>
--dart-define=FIREBASE_PROJECT_ID=<Project ID>
```

Các giá trị trên là cấu hình nhận diện ứng dụng Firebase. Không dùng hoặc đưa Firebase Admin service account vào mobile.

## 2. Bật Firebase Admin ở backend

Tạo service account trong Firebase project, lưu JSON ở nơi an toàn và cấu hình biến môi trường trên máy chủ backend:

```text
FIREBASE_ENABLED=true
FIREBASE_PROJECT_ID=<Project ID>
FIREBASE_SERVICE_ACCOUNT_JSON_BASE64=<service account JSON đã mã hóa Base64>
```

Không commit file service account, không đặt service account trong app Flutter, `--dart-define`, hoặc `mobile/`.

## 3. Gửi giá mới

Backend tạo sự kiện khi giá đã đồng bộ thay đổi so với kỳ trước, sau đó gửi FCM cho thiết bị đã đăng ký theo nhiên liệu, vùng và chiều tăng/giảm đã chọn. Sự kiện dùng ngày hiệu lực UTC; nếu nguồn chỉ có ngày, backend dùng 00:00 UTC của ngày đó. Giá đồng bộ lặp lại nhưng không đổi sẽ không tạo thêm thông báo.

Android 13 trở lên sẽ hỏi quyền thông báo khi người dùng bật tính năng trong Cài đặt. Trên iOS cần thêm iOS app vào Firebase, cấu hình APNs Authentication Key và bật Push Notifications capability trong Xcode.
