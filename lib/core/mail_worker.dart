/// Script name of Edgepost's mail Worker in the user's Cloudflare account,
/// also the name of its D1 database and R2 bucket. Email Routing rules point
/// a `worker` action at it to deliver into the inbox.
const kMailWorkerName = 'edgepost-mail';
