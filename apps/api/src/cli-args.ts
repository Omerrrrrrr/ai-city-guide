export type ParsedCliArgs = Map<string, string | boolean>;

export function parseCliArgs(argv: string[]): ParsedCliArgs {
  const args = new Map<string, string | boolean>();

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];

    if (!token.startsWith('--')) continue;

    const trimmed = token.slice(2);
    const [key, inlineValue] = trimmed.split('=');

    if (inlineValue != null) {
      args.set(key, inlineValue);
      continue;
    }

    const next = argv[index + 1];
    if (next && !next.startsWith('--')) {
      args.set(key, next);
      index += 1;
      continue;
    }

    args.set(key, true);
  }

  return args;
}

export function readStringArg(args: ParsedCliArgs, key: string): string | undefined {
  const value = args.get(key);
  return typeof value === 'string' && value.trim() ? value.trim() : undefined;
}

export function readNumberArg(args: ParsedCliArgs, key: string): number | undefined {
  const value = readStringArg(args, key);
  if (!value) return undefined;

  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

export function hasFlag(args: ParsedCliArgs, key: string): boolean {
  return args.get(key) === true;
}
