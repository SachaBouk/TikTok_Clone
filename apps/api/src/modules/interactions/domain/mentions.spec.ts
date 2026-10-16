import { describe, expect, it } from 'vitest';
import { extractMentions } from './mentions';

describe('extractMentions', () => {
  it('lit les pseudos cités, en minuscules, sans doublon ni point final', () => {
    expect(extractMentions('Merci @Ines.M et @nathan_p ! @ines.m @nathan_p.')).toEqual(['ines.m', 'nathan_p']);
  });

  it('ignore une adresse email, un « @ » seul et un pseudo trop court', () => {
    expect(extractMentions('écris à lea@demo.local, @ ou @a')).toEqual([]);
  });
});
