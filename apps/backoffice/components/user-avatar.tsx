import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';

export function UserAvatar({ user, size }: { user: { displayName: string; avatarUrl: string | null }; size?: 'sm' | 'default' | 'lg' }) {
  return (
    <Avatar size={size}>
      {user.avatarUrl && <AvatarImage src={user.avatarUrl} alt="" />}
      <AvatarFallback>{user.displayName.slice(0, 1).toUpperCase()}</AvatarFallback>
    </Avatar>
  );
}
