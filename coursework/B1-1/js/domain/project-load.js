/** @typedef {"timeout" | "http" | "network" | "payload"} ProjectLoadFailure */

export class ProjectLoadError extends Error {
  /** @param {ProjectLoadFailure} kind @param {string} message @param {ErrorOptions} [options] */
  constructor(kind, message, options) {
    super(message, options);
    /** @readonly */
    this.kind = kind;
  }
}
