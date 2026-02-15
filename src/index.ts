const PORT = process.env.PORT ? parseInt(process.env.PORT, 10) : 3000;

function main(): void {
  console.log(`dev-n8n application starting...`);
  console.log(`Environment: ${process.env.NODE_ENV || "development"}`);
  console.log(`Port: ${PORT}`);
  console.log(`Node.js version: ${process.version}`);
  console.log(`Application is ready.`);
}

main();
