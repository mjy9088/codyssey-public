import { loadGitHubRepositories } from "./data/github.js";
import { initContactForm } from "./ui/contact.js";
import { initNavigation } from "./ui/navigation.js";
import { initProjects } from "./ui/projects.js";
import { initReveals } from "./ui/reveals.js";
import { initTheme } from "./ui/theme.js";

initTheme();
initNavigation();
initContactForm();
initReveals();
initProjects({ loadRepositories: loadGitHubRepositories, startReveals: initReveals });
