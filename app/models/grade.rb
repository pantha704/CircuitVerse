# frozen_string_literal: true

require "cgi"

class Grade < ApplicationRecord
  LETTER_MATCH = /^(A|B|C|D|E|F)$/
  # A spreadsheet treats a cell starting with one of these as a formula, which
  # turns exported user data into CSV injection (OWASP: CSV Injection).
  FORMULA_TRIGGERS = ["=", "+", "-", "@", "\t", "\r"].freeze
  PERCENT_MATCH = /^[0-9][0-9]?$|^100$/

  belongs_to :project
  belongs_to :grader, class_name: "User", foreign_key: :user_id
  belongs_to :assignment

  validates :grade, presence: true
  validate :grading_scale, :assignment_project
  validates :project_id, uniqueness: { scope: :assignment_id }

  private

    def grading_scale
      valid = case assignment.grading_scale
              when "no_scale"
                false
              when "letter"
                grade&.match(LETTER_MATCH).present?
              when "percent"
                grade&.match(PERCENT_MATCH).present?
              when "custom"
                true
      end

      errors.add(:grade, "Grade does not match scale or assignment cannot be graded") unless valid
    end

    def assignment_project
      errors.add(:project, "is not a part of the assignment") if project&.assignment_id != assignment&.id
    end

    # Neutralise a cell so a spreadsheet keeps it as text.
    #
    # Entities are decoded *before* the check on purpose: remarks are written
    # through `sanitize`, so `&#61;SUM(A1)` is stored encoded. Checking the raw
    # string would pass it and let the spreadsheet decode it into a formula.
    def self.csv_cell(value)
      text = CGI.unescapeHTML(value.to_s)
      return text unless text.start_with?(*FORMULA_TRIGGERS)

      "'#{text}"
    end

    def self.to_csv(assignment_id)
      attributes = %w[email name grade remarks]
      group_members = User.joins(group_members: :assignments)
                          .where(group_members: { assignments: { id: assignment_id } })
      submissions = Project.where(assignment_id: assignment_id)&.includes(:grade, :author)

      CSV.generate(headers: true) do |csv|
        csv << attributes

        group_members.each do |member|
          submission = submissions.find do |s|
            s.author_id == member.id &&
              s.assignment_id == assignment_id
          end
          grade = submission&.grade&.grade
          remarks = submission&.grade&.remarks
          grade = grade.presence || "N.A"
          remarks = remarks.presence || "N.A"
          csv << [member.email, member.name, grade, remarks].map { |value| csv_cell(value) }
        end
      end
    end
end
