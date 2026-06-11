// Simulate UTC-5 environment
process.env.TZ = 'America/New_York';
console.log("Timezone set to America/New_York");
console.log("new Date('2026-06-06'):", new Date('2026-06-06').toString());
console.log("getDay():", new Date('2026-06-06').getDay());
