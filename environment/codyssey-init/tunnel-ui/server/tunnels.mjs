import { savedNames, stageService } from './config-file.mjs';
import { summarize, TunnelError, tunnelFromInput } from './policy.mjs';

export function tunnelService(gost, configPath) {
  let saving = false;
  return {
    async ready() {
      await gost.list();
    },
    async list() {
      const services = await gost.list();
      let saved;
      try {
        saved = await savedNames(configPath);
      } catch {
        return {
          tunnels: services.map((service) => summarize(service, true)).map(({ name }) => ({ name, route: 'advanced' })),
          notice: 'The GOST file cannot be safely edited here. Existing services are unchanged.',
        };
      }
      return { tunnels: services.map((service) => summarize(service, saved.has(service.name))) };
    },
    async add(input) {
      const config = tunnelFromInput(input);
      if (saving) throw new TunnelError(409, 'Another tunnel is being added. Try again in a moment.');
      saving = true;
      let stage;
      try {
        if ((await gost.list()).some(({ name }) => name === config.name)) {
          throw new TunnelError(409, 'A tunnel already uses this name.', 'name');
        }
        if (config.handler.chain) await gost.checkTailnet();
        stage = await stageService(configPath, config);
        try {
          await gost.create(config);
        } catch (error) {
          if (error instanceof TunnelError) throw error;
          throw new TunnelError(503, 'GOST did not confirm the start. Reload the list before retrying.');
        }
        try {
          await stage.commit();
        } catch (error) {
          try {
            await gost.remove(config.name);
          } catch {
            throw new TunnelError(503, 'The tunnel was not saved, and GOST did not confirm stopping it. Reload the list.');
          }
          if (error instanceof TunnelError) throw error;
          throw new TunnelError(503, 'The tunnel was stopped because the GOST file could not be saved.');
        }
        return summarize(config, true);
      } finally {
        try {
          await stage?.discard();
        } finally {
          saving = false;
        }
      }
    },
  };
}
