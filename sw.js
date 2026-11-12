self.addEventListener("install", function(){ self.skipWaiting(); });
self.addEventListener("activate", function(e){ e.waitUntil(self.clients.claim()); });
self.addEventListener("push", function(e){
  var d = {};
  try { d = e.data ? e.data.json() : {}; } catch(_){}
  e.waitUntil(self.registration.showNotification(d.title || "Наш простір", {
    body: d.body || "",
    tag: d.tag || "nash",
    icon: "icons/icon-192.png",
    badge: "icons/icon-192.png"
  }));
});
self.addEventListener("notificationclick", function(e){
  e.notification.close();
  e.waitUntil(self.clients.matchAll({type:"window", includeUncontrolled:true}).then(function(list){
    for (var i = 0; i < list.length; i++){ if ("focus" in list[i]) return list[i].focus(); }
    return self.clients.openWindow("./");
  }));
});
