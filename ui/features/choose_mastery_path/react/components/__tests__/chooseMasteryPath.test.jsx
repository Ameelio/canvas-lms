/*
 * Copyright (C) 2016 - present Instructure, Inc.
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

import React from 'react'
import {render} from '@testing-library/react'
import ChooseMasterPath from '../choose-mastery-path'

const defaultProps = () => ({
  options: [
    {
      setId: 1,
      assignments: [
        {
          name: 'Ch 2 Quiz',
          type: 'quiz',
          points: 10,
          due_at: new Date(),
          itemId: 1,
          category: {
            id: 'other',
            label: 'Other',
          },
        },
        {
          name: 'Ch 2 Review',
          type: 'assignment',
          points: 10,
          due_at: new Date(),
          itemId: 1,
          category: {
            id: 'other',
            label: 'Other',
          },
        },
      ],
    },
    {
      setId: 2,
      assignments: [
        {
          name: 'Ch 2 Quiz',
          type: 'quiz',
          points: 10,
          due_at: new Date(),
          itemId: 1,
          category: {
            id: 'other',
            label: 'Other',
          },
        },
        {
          name: 'Ch 2 Review',
          type: 'assignment',
          points: 10,
          due_at: new Date(),
          itemId: 1,
          category: {
            id: 'other',
            label: 'Other',
          },
        },
      ],
    },
  ],
  selectedOption: null,
  selectOption: () => {},
})

describe('Choose Mastery Path', () => {
  it('renders component', () => {
    const {container} = render(<ChooseMasterPath {...defaultProps()} />)
    expect(container.querySelector('.cmp-wrapper')).toBeInTheDocument()
  })

  it('renders all options', () => {
    const {container} = render(<ChooseMasterPath {...defaultProps()} />)
    const options = container.querySelectorAll('.cmp-option')
    expect(options).toHaveLength(2)
  })
})
