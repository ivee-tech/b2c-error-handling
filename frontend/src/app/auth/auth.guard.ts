import { Injectable } from '@angular/core';
import { CanActivate, Router } from '@angular/router';
import { MsalService } from '@azure/msal-angular';

@Injectable({ providedIn: 'root' })
export class AuthGuard implements CanActivate {
  constructor(private msal: MsalService, private router: Router) {}
  canActivate(): boolean {
    const accounts = this.msal.instance.getAllAccounts();
    if (accounts.length === 0) {
      this.msal.loginRedirect();
      return false;
    }
    return true;
  }
}
