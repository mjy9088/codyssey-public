import { initContactForm } from "./contact.js";
import { initNavigation, initReveals } from "./navigation.js";
import { initProjects } from "./projects.js";
import { initTheme } from "./theme.js";

document.documentElement.classList.add("js");
initTheme();
initNavigation();
initContactForm();
initReveals();
initProjects();
