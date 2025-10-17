import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { MsalService, MsalBroadcastService } from '@azure/msal-angular';
import { HttpClient } from '@angular/common/http';
import { filter, firstValueFrom, take, Subject } from 'rxjs';
import { InteractionStatus, AuthenticationResult, EventType, EventMessage, InteractionRequiredAuthError } from '@azure/msal-browser';
import { environment } from '../environments/environment';

@Component({
  standalone: true,
  imports: [CommonModule],
  selector: 'app-root',
  template: `
    <nav class="toolbar">
      <span>Contoso Transit Identity Portal</span>
      <span class="spacer"></span>
      @if (!isLoggedIn()) {
        <button (click)="login()">Login</button>
      } @else {
        <button (click)="logout()">Logout</button>
      }
    </nav>
    <section class="content">
      @if (isLoggedIn()) {
        <h2>Welcome</h2>
        <button (click)="loadProfile()">Reload Profile</button>
      }
      @if (profileJson) {
        <div>
          <h3>Your Profile (from API)</h3>
          <pre>{{ profileJson }}</pre>
        </div>
      } @else {
        <p>Please sign in to view your profile.</p>
      }
    </section>
  `,
  styles: [`
    .toolbar { display: flex; padding: 0.5rem 1rem; background: #004578; color: #fff; align-items: center; }
    .spacer { flex: 1; }
    button { margin-left: 0.5rem; }
    .content { padding: 1rem; font-family: Arial, sans-serif; }
    pre { background: #f5f5f5; padding: 0.75rem; }
  `]
})
export class AppComponent implements OnInit {
  profileJson: string | null = null;
  private loadingProfile = false;
  private loadedOnce = false;
  private destroy$ = new Subject<void>();

  constructor(private msal: MsalService, private http: HttpClient, private msalBroadcast: MsalBroadcastService) {}

  async ngOnInit() {
    if ((this.msal.instance as any).initialize) {
      await this.msal.instance.initialize();
    }
    // If already signed in (page refresh) load once
    if (this.isLoggedIn()) {
      this.loadProfileSafe();
    }

    // Trigger after a successful interactive login
    this.msalBroadcast.msalSubject$
      .pipe(
        filter((msg: EventMessage) => msg.eventType === EventType.LOGIN_SUCCESS),
        take(1)
      )
      .subscribe(() => this.loadProfileSafe());
  }

  isLoggedIn(): boolean {
    return this.msal.instance.getAllAccounts().length > 0;
  }

  login() {
    this.msal.loginRedirect();
  }

  logout() {
    this.msal.logoutRedirect();
  }

  private loadProfileSafe() {
    if (this.loadingProfile || this.loadedOnce) return;
    this.loadingProfile = true;
    this.loadProfile()
      .finally(() => {
        this.loadingProfile = false;
        this.loadedOnce = true;
      });
  }

  async loadProfile() {
    try {
      const account = this.msal.instance.getAllAccounts()[0];
      if (!account) {
        console.warn('No account present, initiating redirect login');
        this.msal.loginRedirect({ scopes: environment.b2c.apiScopes });
        return;
      }
      let tokenResult: AuthenticationResult;
      try {
        tokenResult = await this.msal.instance.acquireTokenSilent({
          scopes: environment.b2c.apiScopes,
          account
        }) as AuthenticationResult;
      } catch (err) {
        if (err instanceof InteractionRequiredAuthError) {
          console.warn('Silent token acquisition failed (interaction required); redirecting.');
          this.msal.loginRedirect({ scopes: environment.b2c.apiScopes });
          return;
        }
        throw err;
      }
      console.debug('Access token acquired exp:', tokenResult.expiresOn?.toISOString());
      const data = await firstValueFrom(this.http.get(environment.api.baseUrl + '/profile'));
      this.profileJson = JSON.stringify(data, null, 2);
    } catch (e) {
      const message = (e as Error).message;
      // Avoid clearing profileJson to prevent repeated attempts
      if (!this.profileJson) {
        this.profileJson = 'Failed to load profile: ' + message;
      }
      console.error('Profile load error', e);
    }
  }
}
