/// Mirrors Profile.isSupporter: paid access until the store marks expired.
export function isSupporterStatus(status: string | null | undefined): boolean {
  return status === 'active' || status === 'grace' || status === 'canceled'
}

export const supporterRequiredMessage =
  'Ao apoiar o GlicoDose, você pode usar o widget da tela inicial, o Health Connect ou o Apple Health e o monitoramento em tempo real com o LibreLinkUp.'

// deno-lint-ignore no-explicit-any
export async function userIsSupporter(admin: any, userId: string): Promise<boolean> {
  const { data, error } = await admin
    .from('profiles')
    .select('supporter_status')
    .eq('id', userId)
    .maybeSingle()
  if (error || !data) return false
  return isSupporterStatus(data.supporter_status as string | null)
}
