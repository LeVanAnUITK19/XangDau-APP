# Giá Xăng Dầu

Ứng dụng Flutter tiếng Việt theo dõi giá xăng dầu, xem lịch sử giá và ước tính chi phí nhiên liệu. Backend TypeScript/Express phục vụ API và đồng bộ dữ liệu vào MongoDB; mobile không kết nối database trực tiếp.

## Tính năng hiện có

- Bốn tab: Giá, Biểu đồ, Tính phí, Cài đặt.
- Giá/lịch sử tải từ API, cache phản hồi gần nhất khi đã có dữ liệu mạng.
- Chọn vùng, xem chi tiết nhiên liệu và biểu đồ bậc thang.
- Máy tính nhiên liệu chạy offline với giá nhập tay.
- API health/readiness, các collection và index MongoDB, endpoint sync có Bearer secret.
- Backend API đăng ký thiết bị, notification outbox và adapter Firebase Admin tùy chọn.
- Docker, Compose, Render Blueprint và GitHub Actions CI/sync schedule.

Giá không được hardcode làm dữ liệu production. Chưa có dữ liệu cho tới khi backend kết nối MongoDB và nhận payload upstream đã xác minh. Upstream/Atlas chưa được kết nối thực tế; Flutter chưa đăng ký thiết bị push, Drift/SQLite chưa được tích hợp và triển khai cloud chưa được xác minh. Xem [trạng thái triển khai](docs/implementation-plan.md).

## Cấu trúc

```text
mobile/                 Flutter application
backend/                Express + TypeScript API
docs/                   Architecture, API, deployment, privacy
.github/workflows/      Backend/mobile CI and scheduled sync
docker-compose.yml      Local backend and MongoDB
render.yaml             Render Blueprint
```

## Bắt đầu backend

```powershell
Copy-Item backend/.env.example backend/.env
# Điền MONGODB_URI và SYNC_SECRET trong backend/.env
cd backend
npm ci
npm run dev
```

API local: `http://localhost:3000/health`, `/ready`, `/api/v1/fuels`, `/api/v1/prices/latest?region=REGION_1`.

## Bắt đầu mobile

```powershell
cd mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

`10.0.2.2` dùng Android emulator; iOS simulator/device dùng địa chỉ API phù hợp của máy chủ phát triển.

## Cấu hình và triển khai

Hướng dẫn đầy đủ: [deployment](docs/deployment.md). Không commit `.env`, Atlas URI, Firebase service account hoặc signing keys. Tài khoản Atlas hiện tìm thấy trong môi trường có một cluster miễn phí đang pause và không khớp hostname URI được cung cấp; cấu hình Atlas đó cần được kiểm tra/khởi động trước.

## Kiểm tra

```powershell
cd backend; npm ci; npm run format:check; npm run lint; npm run typecheck; npm test; npm run build
cd mobile; flutter pub get; dart format --output=none --set-exit-if-changed lib test; flutter analyze; flutter test
```

Lịch sử còn thiếu sẽ được đánh dấu chưa đầy đủ; app không nội suy hoặc bịa ngày điều hành. Notification, API docs/Swagger và real-cloud smoke test chưa sẵn sàng. Xem [API contract](docs/api-contract.md), [database design](docs/database-design.md), [troubleshooting](docs/troubleshooting.md) và [privacy draft](docs/privacy-policy-draft.md).
