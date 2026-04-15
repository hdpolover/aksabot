import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as nodemailer from 'nodemailer';

@Injectable()
export class EmailService {
  private readonly logger = new Logger(EmailService.name);
  private transporter: nodemailer.Transporter | null = null;
  private readonly from: string;
  private readonly configured: boolean;

  constructor(private readonly config: ConfigService) {
    const host = config.get<string>('SMTP_HOST');
    const user = config.get<string>('SMTP_USER');
    const pass = config.get<string>('SMTP_PASS');
    const port = config.get<number>('SMTP_PORT') ?? 587;

    this.from =
      config.get<string>('SMTP_FROM') ?? 'Aksabot <no-reply@aksabot.app>';
    this.configured = !!(host && user && pass);

    if (this.configured) {
      this.transporter = nodemailer.createTransport({
        host,
        port,
        secure: port === 465,
        auth: { user, pass },
      });
      this.logger.log(`SMTP configured — ${host}:${port} as ${user}`);
    } else {
      this.logger.warn(
        'SMTP not configured (SMTP_HOST/SMTP_USER/SMTP_PASS missing) — emails will be logged to console only',
      );
    }
  }

  /**
   * Send a password reset code email.
   * Falls back to console.log if SMTP is not configured (dev mode).
   */
  async sendPasswordReset(
    to: string,
    code: string,
    expiresAt: Date,
  ): Promise<void> {
    const expiryMinutes = Math.round(
      (expiresAt.getTime() - Date.now()) / 60_000,
    );
    const subject = 'Your Aksabot password reset code';
    const text = [
      `Hi,`,
      ``,
      `You requested a password reset for your Aksabot account.`,
      ``,
      `Your reset code is: ${code}`,
      ``,
      `This code expires in ${expiryMinutes} minutes.`,
      ``,
      `If you didn't request this, you can safely ignore this email.`,
      ``,
      `— Aksabot`,
    ].join('\n');

    if (!this.configured || !this.transporter) {
      // Dev fallback — code is visible in server logs
      this.logger.log(
        `[DEV] Password reset email to ${to} — code: ${code} (expires ${expiresAt.toISOString()})`,
      );
      return;
    }

    try {
      await this.transporter.sendMail({
        from: this.from,
        to,
        subject,
        text,
      });
      this.logger.log(`Password reset email sent to ${to}`);
    } catch (err) {
      this.logger.error(
        `Failed to send password reset email to ${to}: ${(err as Error).message}`,
      );
      // Don't rethrow — the code is stored in DB, user can retry or check via support
    }
  }
}
