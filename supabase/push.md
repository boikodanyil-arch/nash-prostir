# Push-сповіщення

Вже застосовано до бази (міграція `push_notifications`) і розгорнуто Edge Function `notify`.
- Таблиця `push_subscriptions` + RPC `push_subscribe`, `push_unsubscribe`, `push_public_key`.
- Тригер `items_notify` викликає функцію `notify` після кожного нового запису.
- VAPID-ключі створюються функцією при першому запуску й зберігаються в `private.app_config`.
