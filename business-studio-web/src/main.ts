import { bootstrapApplication } from '@angular/platform-browser';
import { setAssetPath } from 'ionicons';
import { defineCustomElements } from 'ionicons/loader';
import { appConfig } from './app/app.config';
import { App } from './app/app';

setAssetPath('/ionicons/');
defineCustomElements(window);

bootstrapApplication(App, appConfig)
  .catch((err) => console.error(err));
