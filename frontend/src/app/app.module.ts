import { NgModule } from '@angular/core';
import { BrowserModule } from '@angular/platform-browser';
import { RouterModule, Routes } from '@angular/router';
import { HTTP_INTERCEPTORS, HttpClientModule } from '@angular/common/http';
import { MsalModule, MsalRedirectComponent, MsalGuard, MsalBroadcastService, MsalGuardConfiguration, MsalInterceptor, MsalInterceptorConfiguration } from '@azure/msal-angular';
import { PublicClientApplication, InteractionType } from '@azure/msal-browser';
import { environment } from '../environments/environment';
import { AuthGuard } from './auth/auth.guard';
import { AppComponent } from './app.component';

const routes: Routes = [
  { path: '', component: AppComponent },
  { path: 'profile', component: AppComponent, canActivate: [MsalGuard, AuthGuard] }
];

export function MSALInstanceFactory() {
  const { tenant, clientId, signInSignUpPolicy, authorityDomain } = environment.b2c;
  return new PublicClientApplication({
    auth: {
      clientId,
      authority: `https://${authorityDomain}/${tenant}/${signInSignUpPolicy}`,
      knownAuthorities: [authorityDomain],
      redirectUri: environment.b2c.redirectUri,
      postLogoutRedirectUri: environment.b2c.postLogoutRedirectUri
    },
    cache: {
      cacheLocation: 'localStorage',
      storeAuthStateInCookie: false
    }
  });
}

export function MSALGuardConfigFactory(): MsalGuardConfiguration {
  return {
    interactionType: InteractionType.Redirect,
    authRequest: {
      scopes: environment.b2c.apiScopes
    }
  };
}

export function MSALInterceptorConfigFactory(): MsalInterceptorConfiguration {
  return {
    interactionType: InteractionType.Redirect,
    protectedResourceMap: new Map([
      // Map base API and explicit profile endpoint to requested scopes
      [environment.api.baseUrl, environment.b2c.apiScopes],
      [environment.api.baseUrl + '/profile', environment.b2c.apiScopes]
    ])
  };
}

@NgModule({
  imports: [
    BrowserModule,
    HttpClientModule,
    RouterModule.forRoot(routes),
    MsalModule.forRoot(
      MSALInstanceFactory(),
      MSALGuardConfigFactory(),
      MSALInterceptorConfigFactory()
    ),
    AppComponent
  ],
  providers: [
    MsalGuard,
    MsalBroadcastService,
    AuthGuard,
    { provide: HTTP_INTERCEPTORS, useClass: MsalInterceptor, multi: true }
  ],
  bootstrap: [AppComponent, MsalRedirectComponent]
})
export class AppModule {}
