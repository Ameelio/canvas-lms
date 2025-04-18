/*
 * Copyright (C) 2024 - present Instructure, Inc.
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
import {fireEvent, render, screen} from '@testing-library/react'
import userEvent from '@testing-library/user-event'

import {speedGraderUrl} from '../../assignment/AssignmentApi'
import GradesGrid from '../GradesGrid/index'
import {STARTED} from '../../grades/GradeActions'

describe('GradeSummary GradesGrid', () => {
  let props
  let wrapper

  beforeEach(() => {
    props = {
      anonymousStudents: false,
      assignment: {
        courseId: '1201',
        id: '2301',
      },
      disabledCustomGrade: false,
      finalGrader: {
        graderId: 'teach',
        id: '1105',
      },
      graders: [
        {graderId: '1101', graderName: 'Miss Frizzle'},
        {graderId: '1102', graderName: 'Mr. Keating'},
      ],
      grades: {
        1111: {
          teach: {
            grade: '55',
            graderId: 'teach',
            id: '4605',
            score: 55,
            selected: false,
            studentId: '1111',
          },
          1101: {
            grade: 'A',
            graderId: '1101',
            id: '4601',
            score: 10,
            selected: false,
            studentId: '1111',
          },
          1102: {
            grade: 'B',
            graderId: '1102',
            id: '4602',
            score: 8.9,
            selected: false,
            studentId: '1111',
          },
        },
        1112: {
          1102: {
            grade: 'C',
            graderId: '1102',
            id: '4603',
            score: 7.8,
            selected: false,
            studentId: '1112',
          },
        },
        1113: {
          1101: {
            grade: 'A',
            graderId: '1101',
            id: '4604',
            score: 10,
            selected: false,
            studentId: '1113',
          },
        },
      },
      onGradeSelect: jest.fn(),
      selectProvisionalGradeStatuses: {},
      students: [
        {id: '1111', displayName: 'Adam Jones'},
        {id: '1112', displayName: 'Betty Ford'},
        {id: '1113', displayName: 'Charlie Xi'},
        {id: '1114', displayName: 'Dana Smith'},
      ],
    }
  })

  function mountComponent() {
    wrapper = render(<GradesGrid {...props} />)
  }

  function getGraderNames() {
    const headers = wrapper.container.querySelectorAll('th.GradesGrid__GraderHeader')
    return [...headers].map(header => header.textContent)
  }

  function getStudentNames() {
    const headers = wrapper.container.querySelectorAll('th.GradesGrid__BodyRowHeader')
    return [...headers].map(header => header.textContent)
  }

  function speedGraderUrlFor(studentId, anonymousStudents = false) {
    return speedGraderUrl('1201', '2301', {anonymousStudents, studentId})
  }

  it('displays the grader names in the column headers', () => {
    mountComponent()
    expect(getGraderNames()).toEqual(['Miss Frizzle', 'Mr. Keating'])
  })

  it('includes a row for each student', () => {
    mountComponent()
    expect(wrapper.container.querySelectorAll('tr.GradesGrid__BodyRow')).toHaveLength(4)
  })

  it('sends disabledCustomGrade to the Grid', () => {
    props.disabledCustomGrade = true

    mountComponent()

    fireEvent.change(
      screen.getByRole('combobox', {
        name: /grade for Adam Jones/i,
      }),
      {target: {value: '10'}},
    )

    expect(
      screen.queryByRole('option', {
        name: /10 \(custom\)/i,
      }),
    ).not.toBeInTheDocument()
  })

  it('sends finalGrader to the Grid', () => {
    mountComponent()

    fireEvent.change(
      screen.getByRole('combobox', {
        name: /grade for Adam Jones/i,
      }),
      {target: {value: '55'}},
    )

    expect(
      screen.queryByRole('option', {
        name: /55 \(custom\)/i,
      }),
    ).toBeInTheDocument()
  })

  it('sends graders to the Grid', () => {
    mountComponent()

    props.graders.forEach(grader => expect(screen.getByText(grader.graderName)).toBeInTheDocument())
  })

  it('sends onGradeSelect to the Grid', () => {
    props.disabledCustomGrade = false

    mountComponent()

    fireEvent.change(
      screen.getByRole('combobox', {
        name: /grade for Adam Jones/i,
      }),
      {target: {value: '10'}},
    )
    fireEvent.click(
      screen.getByRole('option', {
        name: /10 \(custom\)/i,
      }),
    )

    expect(props.onGradeSelect).toHaveBeenCalledWith({
      grade: '55',
      graderId: 'teach',
      id: '4605',
      score: 10,
      selected: false,
      studentId: '1111',
    })
  })

  it('sends selectProvisionalGradeStatuses to the Grid', () => {
    props.selectProvisionalGradeStatuses = {1111: STARTED}

    mountComponent()

    expect(
      screen.getByRole('combobox', {
        name: /grade for Adam Jones/i,
      }),
    ).toBeInTheDocument()
  })

  it('adds rows as students are added', () => {
    const {students} = props
    props.students = students.slice(0, 2)
    mountComponent()
    props.students = students
    wrapper.rerender(<GradesGrid {...props} />)
    expect(wrapper.container.querySelectorAll('tr.GradesGrid__BodyRow')).toHaveLength(4)
  })

  it('displays the student names in the row headers', () => {
    mountComponent()
    expect(getStudentNames()).toEqual(['Adam Jones', 'Betty Ford', 'Charlie Xi', 'Dana Smith'])
  })

  it('links the student names to SpeedGrader', () => {
    mountComponent()
    const links = wrapper.container.querySelectorAll('th.GradesGrid__BodyRowHeader a')
    const expectedUrls = props.students.map(student => speedGraderUrlFor(student.id))
    expect([...links].map(link => link.getAttribute('href'))).toEqual(expectedUrls)
  })

  it('enumerates students for names when students are anonymous', () => {
    for (let i = 0; i < props.students.length; i++) {
      props.students[i].displayName = null
    }
    mountComponent()
    expect(getStudentNames()).toEqual(['Student 1', 'Student 2', 'Student 3', 'Student 4'])
  })

  it('anonymizes student links to SpeedGrader when students are anonymous', () => {
    props.anonymousStudents = true
    mountComponent()
    const links = wrapper.container.querySelectorAll('th.GradesGrid__BodyRowHeader a')
    const expectedUrls = props.students.map(student => speedGraderUrlFor(student.id, true))
    expect([...links].map(link => link.getAttribute('href'))).toEqual(expectedUrls)
  })

  it('sorts students by id when students are anonymous', () => {
    props.students = [
      {id: 'fp312', displayName: 'Adam Jones'},
      {id: 'BB811', displayName: 'Betty Ford'},
      {id: 'x9X23', displayName: 'Charlie Xi'},
      {id: 'G234a', displayName: 'Dana Smith'},
    ]
    props.anonymousStudents = true
    mountComponent()
    const links = wrapper.container.querySelectorAll('th.GradesGrid__BodyRowHeader a')
    const sortedStudentIds = ['BB811', 'G234a', 'fp312', 'x9X23']
    const expectedUrls = sortedStudentIds.map(id => speedGraderUrlFor(id, true))
    expect([...links].map(link => link.getAttribute('href'))).toEqual(expectedUrls)
  })

  it('enumerates additional students for names as they are added', () => {
    for (let i = 0; i < props.students.length; i++) {
      props.students[i].displayName = null
    }
    const {students} = props
    props.students = students.slice(0, 2)
    mountComponent()
    props.students = students
    wrapper.rerender(<GradesGrid {...props} />)
    expect(getStudentNames()).toEqual(['Student 1', 'Student 2', 'Student 3', 'Student 4'])
  })

  it('does not display page navigation when only one page of students is loaded', () => {
    mountComponent()
    expect(screen.queryByRole('navigation')).toBeNull()
  })

  describe('when multiple pages of students are loaded', () => {
    beforeEach(() => {
      props.students = []
      for (let id = 1111; id <= 1160; id++) {
        props.students.push({id: `${id}`, displayName: `Student ${id}`})
      }
    })

    it('displays page navigation', () => {
      mountComponent()
      expect(screen.getByRole('navigation')).toBeInTheDocument()
    })

    it('displays only 20 rows on a page', () => {
      mountComponent()
      expect(wrapper.container.querySelectorAll('tr.GradesGrid__BodyRow')).toHaveLength(20)
    })

    it('displays the first 20 students on the first page', () => {
      mountComponent()
      const expectedNames = props.students.slice(0, 20).map(student => student.displayName)
      expect(getStudentNames()).toEqual(expectedNames)
    })

    it('displays the next 20 students after navigating to the second page', async () => {
      const user = userEvent.setup({delay: null})
      mountComponent()
      await user.click(screen.getByRole('button', {name: /2/i}))
      const expectedNames = props.students.slice(20, 40).map(student => student.displayName)
      expect(getStudentNames()).toEqual(expectedNames)
    })

    it('updates the current page as students are added', async () => {
      const user = userEvent.setup({delay: null})
      const {students} = props
      props.students = students.slice(0, 30) // page 2 has 10 students
      mountComponent()
      await user.click(screen.getByRole('button', {name: /2/i}))
      props.students = students
      wrapper.rerender(<GradesGrid {...props} />)
      const expectedNames = students.slice(20, 40).map(student => student.displayName)
      expect(getStudentNames()).toEqual(expectedNames)
    })

    it('continues enumeration on students across pages', async () => {
      const user = userEvent.setup({delay: null})
      const anonymousNames = []
      for (let i = 0; i < props.students.length; i++) {
        props.students[i].displayName = null
        anonymousNames.push(`Student ${i + 1}`)
      }
      mountComponent()
      await user.click(screen.getByRole('button', {name: /2/i}))
      // Student 21, Student 22, ..., Student 40
      expect(getStudentNames()).toEqual(anonymousNames.slice(20, 40))
    })
  })
})
