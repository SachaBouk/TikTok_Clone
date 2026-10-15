import { Controller, Get } from '@nestjs/common';
import { ApiOkResponse, ApiTags } from '@nestjs/swagger';
import type { InterestCatalogDto } from '@repo/shared';
import { Public } from '../../auth/interfaces/public.decorator';
import { UsersService } from '../application/users.service';
import { InterestCatalogResponse, toInterestDto } from './interests.responses';

// Catalogue des centres d'intérêt (ADR-055), public : l'écran est montré pendant l'inscription.
@ApiTags('users')
@Controller('interests')
export class InterestsController {
  constructor(private readonly usersService: UsersService) {}

  @Public()
  @Get('catalog')
  @ApiOkResponse({ type: InterestCatalogResponse })
  getInterestCatalog(): InterestCatalogDto {
    return { items: this.usersService.interestCatalog().map(toInterestDto) };
  }
}
