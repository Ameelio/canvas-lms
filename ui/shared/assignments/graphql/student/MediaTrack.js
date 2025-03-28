/*
 * Copyright (C) 2019 - present Instructure, Inc.
 *
 * This file is part of Canvas.
 *
 * Canvas is free software: you can redistribute it and/or modify it under
 * the terms of the GNU Affero General Public License as published by the Free
 * Software Foundation, version 3 of the License.
 *
 * Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
 * A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
 * details.
 *
 * You should have received a copy of the GNU Affero General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */
import {gql} from '@apollo/client'
import {shape, string} from 'prop-types'

export const MediaTrack = {
  fragment: gql`
    fragment MediaTrack on MediaTrack {
      _id
      locale
      content
      kind
    }
  `,

  shape: shape({
    _id: string,
    locale: string,
    content: string,
    kind: string,
  }),
}

export const DefaultMocks = {
  MediaTrack: () => ({
    _id: '1',
    locale: 'en',
    content: 'en',
    kind: 'subtitle',
  }),
}
