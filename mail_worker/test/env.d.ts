declare namespace Cloudflare {
  interface Env {
    DB: D1Database;
    MAIL: R2Bucket;
    EMAIL: SendEmail;
    MAIL_API_KEY: string;
  }
}
